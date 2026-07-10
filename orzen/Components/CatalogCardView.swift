import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

#if os(macOS)
private typealias OrzenPlatformImage = NSImage
#else
private typealias OrzenPlatformImage = UIImage
#endif

struct CachedRemoteImage<Content: View, Placeholder: View>: View {
    let url: URL
    let fallbackURL: URL?
    let content: (Image) -> Content
    let placeholder: (Bool) -> Placeholder

    init(
        url: URL,
        fallbackURL: URL? = nil,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping (Bool) -> Placeholder
    ) {
        self.url = url
        self.fallbackURL = fallbackURL
        self.content = content
        self.placeholder = placeholder
    }
    
    @StateObject private var loader = CachedRemoteImageLoader()
    
    var body: some View {
        Group {
            if let image = loader.image {
                content(Image(orzenPlatformImage: image))
            } else {
                placeholder(loader.isLoading)
            }
        }
        .onAppear {
            loader.load(url, fallbackURL: fallbackURL)
        }
        .onChange(of: ImageRequest(url: url, fallbackURL: fallbackURL)) { _, request in
            loader.load(request.url, fallbackURL: request.fallbackURL)
        }
    }
}

private struct ImageRequest: Equatable {
    let url: URL
    let fallbackURL: URL?
}

@MainActor
private final class CachedRemoteImageLoader: ObservableObject {
    private static let cache: NSCache<NSURL, OrzenPlatformImage> = {
        let cache = NSCache<NSURL, OrzenPlatformImage>()
        cache.countLimit = 220
        cache.totalCostLimit = 120 * 1024 * 1024
        return cache
    }()
    
    @Published private(set) var image: OrzenPlatformImage?
    @Published private(set) var isLoading = true
    
    private var currentRequest: ImageRequest?
    private var requestID = UUID()
    private var loadTask: Task<Void, Never>?
    
    func load(_ url: URL, fallbackURL: URL? = nil) {
        let request = ImageRequest(url: url, fallbackURL: fallbackURL)

        if currentRequest != request {
            loadTask?.cancel()
            loadTask = nil
            currentRequest = request
            requestID = UUID()
            image = nil
            isLoading = true
        }

        for candidateURL in Self.candidateURLs(for: request) {
            if let cachedImage = Self.cache.object(forKey: candidateURL as NSURL) {
                image = cachedImage
                isLoading = false
                return
            }
        }
        
        guard loadTask == nil else { return }

        let activeRequestID = requestID
        loadTask = Task {
            defer {
                Task { @MainActor in
                    guard self.requestID == activeRequestID else { return }
                    self.loadTask = nil
                }
            }

            for candidateURL in Self.candidateURLs(for: request) {
                do {
                    let (data, response) = try await URLSession.shared.data(from: candidateURL)
                    guard !Task.isCancelled,
                          let httpResponse = response as? HTTPURLResponse,
                          (200..<300).contains(httpResponse.statusCode),
                          let loadedImage = OrzenPlatformImage(data: data) else {
                        continue
                    }

                    await MainActor.run {
                        guard self.requestID == activeRequestID else { return }
                        Self.cache.setObject(loadedImage, forKey: candidateURL as NSURL, cost: data.count)
                        self.image = loadedImage
                        self.isLoading = false
                    }
                    return
                } catch where Task.isCancelled {
                    return
                } catch {
                    continue
                }
            }

            await MainActor.run {
                guard self.requestID == activeRequestID else { return }
                self.isLoading = false
            }
        }
    }

    static func prefetch(url: URL, fallbackURL: URL? = nil) {
        let request = ImageRequest(url: url, fallbackURL: fallbackURL)

        guard !candidateURLs(for: request).contains(where: { cache.object(forKey: $0 as NSURL) != nil }) else {
            return
        }

        Task {
            for candidateURL in candidateURLs(for: request) {
                do {
                    let (data, response) = try await URLSession.shared.data(from: candidateURL)
                    guard !Task.isCancelled,
                          let httpResponse = response as? HTTPURLResponse,
                          (200..<300).contains(httpResponse.statusCode),
                          let image = OrzenPlatformImage(data: data) else {
                        continue
                    }

                    cache.setObject(image, forKey: candidateURL as NSURL, cost: data.count)
                    return
                } catch where Task.isCancelled {
                    return
                } catch {
                    continue
                }
            }
        }
    }

    private static func candidateURLs(for request: ImageRequest) -> [URL] {
        [request.url, request.fallbackURL]
            .compactMap { $0 }
            .reduce(into: []) { urls, url in
                guard !urls.contains(url) else { return }
                urls.append(url)
            }
    }
    
    deinit {
        loadTask?.cancel()
    }
}

enum RemoteImagePrefetcher {
    @MainActor
    static func prefetch(url: URL, fallbackURL: URL? = nil) {
        CachedRemoteImageLoader.prefetch(url: url, fallbackURL: fallbackURL)
    }
}

private extension Image {
    init(orzenPlatformImage image: OrzenPlatformImage) {
        #if os(macOS)
        self.init(nsImage: image)
        #else
        self.init(uiImage: image)
        #endif
    }
}

struct OrzenArtworkPlaceholder: View {
    enum Style {
        case poster
        case backdrop
    }
    
    let style: Style
    
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.white.opacity(0.16),
                    Color.white.opacity(0.07),
                    Color.white.opacity(0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            Image(systemName: style == .poster ? "film" : "photo")
                .font(.system(size: style == .poster ? 34 : 52, weight: .medium))
                .foregroundColor(.white.opacity(0.34))
        }
    }
}

struct CatalogCardView: View {
    let item: CatalogItem
    let width: CGFloat
    let height: CGFloat
    @State private var isHovered = false
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let imageName = item.imageName, !imageName.isEmpty {
                Image(imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                OrzenArtworkPlaceholder(style: .poster)
            }
        }
        .frame(width: width, height: height)
        .cornerRadius(8)
        .overlay(
            ZStack {
                Rectangle()
                    .fill(Color.black.opacity(0.4))
                    .cornerRadius(8)
                Text(item.title)
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(8)
                    .shadow(radius: 4)
                    .multilineTextAlignment(.center)
            }
            .opacity(isHovered ? 1 : 0)
            .animation(.easeInOut(duration: 0.2), value: isHovered),
            alignment: .center
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .clipped()
    }
}

struct CatalogCardView_Previews: PreviewProvider {
    static var previews: some View {
        CatalogCardView(item: lastWatched[0], width: 160, height: 240)
    }
} 
