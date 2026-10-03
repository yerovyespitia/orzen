import SwiftUI

struct DownloadsView: View {
    var popToRootRequest = 0
    var ownsNavigationStack = true

    #if os(macOS)
    @ObservedObject private var library = LocalMediaLibraryStore.shared
    @ObservedObject private var service = LocalMediaServiceController.shared
    #else
    @State private var remoteVersions: [LocalMediaVersion] = []
    @State private var connectionError: String?
    #endif
    @State private var fetchedItems: [String: CatalogItem] = [:]

    private var versions: [LocalMediaVersion] {
        #if os(macOS)
        library.versions
        #else
        remoteVersions
        #endif
    }

    private var entries: [DownloadCatalogEntry] {
        Dictionary(grouping: versions, by: { "\($0.contentType.rawValue):\($0.catalogID)" })
            .compactMap { key, versions in
                guard let first = versions.first else { return nil }
                return DownloadCatalogEntry(id: key, catalogID: first.catalogID,
                    type: first.contentType, versions: versions)
            }
            .sorted { item(for: $0).title.localizedStandardCompare(item(for: $1).title) == .orderedAscending }
    }

    var body: some View {
        Group {
            if ownsNavigationStack {
                NavigationStack { content }
            } else {
                content
            }
        }
        #if os(iOS)
        .toolbar(ownsNavigationStack ? .hidden : .visible, for: .navigationBar)
        .interactivePopGestureEnabled()
        .task {
            while !Task.isCancelled {
                do {
                    remoteVersions = try await RemoteLocalMediaClient.shared.versions()
                    connectionError = nil
                } catch {
                    connectionError = error.localizedDescription
                }
                try? await Task.sleep(for: .seconds(3))
            }
        }
        #endif
        .task(id: entries.map(\.id)) {
            for entry in entries where entry.versions.allSatisfy({ $0.catalogItem == nil }) {
                guard fetchedItems[entry.id] == nil, !Task.isCancelled else { continue }
                if let item = try? await CinemetaClient.fetchItem(type: entry.type, id: entry.catalogID) {
                    fetchedItems[entry.id] = item
                    try? await RemoteLocalMediaClient.shared.updateMetadata(item)
                }
            }
        }
    }

    private var content: some View {
        OrzenCollectionScreen(title: "Downloads") {
            if entries.isEmpty {
                emptyContent
                    .orzenScreenContentInset()
            } else {
                OrzenScreenScrollView {
                    #if os(macOS)
                    if let error = service.errorMessage {
                        Text(error + " Showing the last known downloads.")
                            .font(.callout).foregroundStyle(.secondary)
                            .padding(.bottom, 16)
                    }
                    #endif
                    OrzenPosterGrid {
                        ForEach(entries) { entry in
                            let item = item(for: entry)
                            NavigationLink(destination: InfoView(item: item)) {
                                CatalogPosterCard(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        #if os(iOS)
        .popNavigationToRoot(on: popToRootRequest)
        #endif
    }

    private var emptyContent: some View {
        DetailUnavailableView(
            systemImage: "arrow.down.to.line",
            title: "No downloads yet",
            message: emptyMessage
        )
    }

    private var emptyMessage: String {
        #if os(iOS)
        connectionError ?? "Download a movie or episode on your Mac to see it here."
        #else
        service.errorMessage ?? "Download a movie or episode to see it here."
        #endif
    }

    private func item(for entry: DownloadCatalogEntry) -> CatalogItem {
        if let saved = entry.versions.compactMap(\.catalogItem).first { return saved }
        if let fetched = fetchedItems[entry.id] { return fetched }
        let release = entry.versions[0].torrentTitle
        let marker = release.range(of: #"\b(?:S\d{1,2}E\d{1,2}|(?:19|20)\d{2})\b"#,
            options: [.regularExpression, .caseInsensitive])
        let prefix = marker.map { String(release[..<$0.lowerBound]) } ?? release
        let title = prefix.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return CatalogItem(id: entry.catalogID, title: title.isEmpty ? release : title,
            description: "No description available.", cinemetaType: entry.type)
    }
}

private struct DownloadCatalogEntry: Identifiable {
    let id: String
    let catalogID: String
    let type: CinemetaType
    let versions: [LocalMediaVersion]
}
