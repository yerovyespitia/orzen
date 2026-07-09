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
    let content: (Image) -> Content
    let placeholder: (Bool) -> Placeholder
    
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
            loader.load(url)
        }
        .onChange(of: url) { _, newURL in
            loader.load(newURL)
        }
    }
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
    
    private var currentURL: URL?
    private var loadTask: Task<Void, Never>?
    
    func load(_ url: URL) {
        if currentURL != url {
            loadTask?.cancel()
            currentURL = url
            image = nil
            isLoading = true
        }
        
        if let cachedImage = Self.cache.object(forKey: url as NSURL) {
            image = cachedImage
            isLoading = false
            return
        }
        
        guard loadTask == nil else { return }
        
        loadTask = Task {
            defer {
                Task { @MainActor in
                    self.loadTask = nil
                }
            }
            
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard !Task.isCancelled,
                      let httpResponse = response as? HTTPURLResponse,
                      (200..<300).contains(httpResponse.statusCode),
                      let loadedImage = OrzenPlatformImage(data: data) else {
                    await MainActor.run {
                        guard self.currentURL == url else { return }
                        self.isLoading = false
                    }
                    return
                }
                
                await MainActor.run {
                    Self.cache.setObject(loadedImage, forKey: url as NSURL, cost: data.count)
                    if self.currentURL == url {
                        self.image = loadedImage
                        self.isLoading = false
                    }
                }
            } catch where !Task.isCancelled {
                await MainActor.run {
                    guard self.currentURL == url else { return }
                    self.isLoading = false
                }
            } catch {
                return
            }
        }
    }
    
    deinit {
        loadTask?.cancel()
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
