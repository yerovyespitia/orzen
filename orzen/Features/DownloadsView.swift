import SwiftUI

struct DownloadsView: View {
    var popToRootRequest = 0

    #if os(macOS)
    @ObservedObject private var library = LocalMediaLibraryStore.shared
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
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 20) {
                    #if os(macOS)
                    Text("Downloads")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                    #endif

                    if entries.isEmpty {
                        emptyContent
                    } else {
                        ScrollView {
                            LazyVGrid(columns: OrzenLayout.posterGridColumns,
                                alignment: .leading, spacing: OrzenLayout.current.gridVerticalSpacing) {
                                ForEach(entries) { entry in
                                    let item = item(for: entry)
                                    NavigationLink(destination: InfoView(item: item)) {
                                        CatalogPosterCard(item: item)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, OrzenLayout.current.contentLeadingInset)
                            .padding(.bottom, 24)
                        }
                        .orzenTopScrollEdgeEffect()
                    }
                }
            }
            .navigationTitle("Downloads")
            #if os(iOS)
            .popNavigationToRoot(on: popToRootRequest)
            #endif
        }
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
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
                    #if os(macOS)
                    for version in entry.versions {
                        var updated = version
                        updated.catalogItem = item
                        try? library.update(updated)
                    }
                    #endif
                }
            }
        }
    }

    private var emptyContent: some View {
        ContentUnavailableView {
            Label("No downloads yet", systemImage: "arrow.down.to.line")
        } description: {
            #if os(iOS)
            Text(connectionError ?? "Download a movie or episode on your Mac to see it here.")
            #else
            Text("Download a movie or episode to see it here.")
            #endif
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
