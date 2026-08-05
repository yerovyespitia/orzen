import Foundation

struct StreamSourceAddonResult: Sendable {
    let addon: LocalAddon
    let sources: [StreamSource]
}

enum StreamSourceResolver {
    typealias SourceFetcher = @Sendable (LocalAddon, CinemetaType, String) async -> [StreamSource]

    private static let addonFetchTimeoutSeconds: UInt64 = 12

    static func sourceResults(
        from addons: [LocalAddon],
        type: CinemetaType,
        id: String
    ) -> AsyncStream<StreamSourceAddonResult> {
        sourceResults(
            from: addons,
            type: type,
            id: id,
            fetch: { addon, type, id in
                await fetchSourcesWithTimeout(from: addon, type: type, id: id)
            }
        )
    }

    static func sourceResults(
        from addons: [LocalAddon],
        type: CinemetaType,
        id: String,
        fetch: @escaping SourceFetcher
    ) -> AsyncStream<StreamSourceAddonResult> {
        AsyncStream { continuation in
            let task = Task {
                await withTaskGroup(of: StreamSourceAddonResult.self) { group in
                    for addon in addons {
                        group.addTask {
                            let sources = await fetch(addon, type, id)
                            return StreamSourceAddonResult(
                                addon: addon,
                                sources: sortedSourcesForCurrentPlatform(sources)
                            )
                        }
                    }

                    for await result in group {
                        guard !Task.isCancelled else { break }
                        continuation.yield(result)
                    }
                }
                continuation.finish()
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    static func fetchSourcesByAddon(
        from addons: [LocalAddon],
        type: CinemetaType,
        id: String
    ) async -> [LocalAddon.ID: [StreamSource]] {
        var sourcesByAddonID: [LocalAddon.ID: [StreamSource]] = [:]
        for await result in sourceResults(from: addons, type: type, id: id) {
            sourcesByAddonID[result.addon.id] = result.sources
        }
        return sourcesByAddonID
    }

    static func fetchAllSources(
        from addons: [LocalAddon],
        type: CinemetaType,
        id: String
    ) async -> [StreamSource] {
        let sourcesByAddonID = await fetchSourcesByAddon(from: addons, type: type, id: id)
        let allSources = addons.flatMap { sourcesByAddonID[$0.id] ?? [] }
        return sortedSourcesForCurrentPlatform(allSources)
    }

    static func sortedSources(_ sources: [StreamSource]) -> [StreamSource] {
        sortedSourcesForCurrentPlatform(sources)
    }

    static func firstSource(
        from addons: [LocalAddon],
        type: CinemetaType,
        id: String
    ) async -> StreamSource? {
        for await result in sourceResults(from: addons, type: type, id: id) {
            if let source = firstPlayableSourceForCurrentPlatform(in: result.sources) {
                return source
            }
        }

        return nil
    }

    static func continuingSource(
        after source: StreamSource,
        preferredTitle: String? = nil,
        from addons: [LocalAddon],
        type: CinemetaType,
        id: String
    ) async -> StreamSource? {
        let matchingAddons = sourceAddons(for: source, from: addons)
        let sourcesByAddonID = await fetchSourcesByAddon(
            from: matchingAddons,
            type: type,
            id: id
        )

        for addon in matchingAddons {
            let sources = sourcesByAddonID[addon.id] ?? []
            if let matchingBranch = matchingBranch(
                for: source,
                preferredTitle: preferredTitle,
                in: sources
            ) {
                return matchingBranch
            }
        }

        for addon in matchingAddons {
            let sources = sourcesByAddonID[addon.id] ?? []
            if let fallback = matchingSource(for: source, in: sources) {
                return fallback
            }
        }

        return nil
    }

    static func sourceAddons(
        for source: StreamSource,
        from addons: [LocalAddon]
    ) -> [LocalAddon] {
        if let addonID = source.addonID {
            return addons.first(where: { $0.id == addonID }).map { [$0] } ?? []
        }

        return addons.filter {
            $0.name == source.addonName && $0.sourceCategory == source.sourceCategory
        }
    }

    static func matchingSource(
        for storedSource: StreamSource,
        in sources: [StreamSource]
    ) -> StreamSource? {
        let matchedSource = sources.first { $0.id == storedSource.id }
            ?? sources.first { $0.playbackURL == storedSource.playbackURL }
            ?? sources.first { $0.title == storedSource.title }

        #if os(iOS)
        if let matchedSource,
           NativePlaybackCompatibilityResolver.compatibility(for: matchedSource).canAttemptPlayback {
            return matchedSource
        }

        return NativePlaybackCompatibilityResolver.bestNativeSource(in: sources)
            ?? matchedSource
            ?? sources.first
        #else
        return matchedSource ?? sources.first
        #endif
    }

    private static func matchingBranch(
        for storedSource: StreamSource,
        preferredTitle: String?,
        in sources: [StreamSource]
    ) -> StreamSource? {
        let sameAddonSources = sources.filter {
            $0.addonName == storedSource.addonName
                && $0.sourceCategory == storedSource.sourceCategory
        }
        let resolvedPreferredTitle = preferredTitle ?? storedSource.title
        let matchedSource = sameAddonSources.first { $0.title == resolvedPreferredTitle }
            ?? sameAddonSources.first {
                $0.title.localizedCaseInsensitiveCompare(resolvedPreferredTitle) == .orderedSame
            }
            ?? sameAddonSources.first { $0.id == storedSource.id }
            ?? sameAddonSources.first { $0.playbackURL == storedSource.playbackURL }
            ?? sameAddonSources.first { $0.title == storedSource.title }
            ?? storedSource.addonSourceIndex.flatMap { storedIndex in
                sameAddonSources.first { $0.addonSourceIndex == storedIndex }
            }

        return matchedSource
    }

    private static func sortedSourcesForCurrentPlatform(_ sources: [StreamSource]) -> [StreamSource] {
        #if os(iOS)
        return NativePlaybackCompatibilityResolver.sortedForNativePlayback(sources)
        #else
        return sources
        #endif
    }

    private static func firstPlayableSourceForCurrentPlatform(in sources: [StreamSource]) -> StreamSource? {
        #if os(iOS)
        return NativePlaybackCompatibilityResolver.bestNativeSource(in: sources) ?? sources.first
        #else
        return sources.first
        #endif
    }

    private static func fetchSourcesWithTimeout(
        from addon: LocalAddon,
        type: CinemetaType,
        id: String
    ) async -> [StreamSource] {
        await withTaskGroup(of: [StreamSource]?.self) { group in
            group.addTask {
                (try? await StremioStreamClient.fetchSources(from: addon, type: type, id: id)) ?? []
            }

            group.addTask {
                try? await Task.sleep(nanoseconds: addonFetchTimeoutSeconds * 1_000_000_000)
                return nil
            }

            let sources = await group.next() ?? nil
            group.cancelAll()
            return sources ?? []
        }
    }
}
