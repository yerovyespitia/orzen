import SwiftUI

#if os(iOS)
import UIKit

struct iPhoneRootShell: View {
    @ObservedObject private var playbackStore = StreamPlaybackStore.shared
    @State private var selectedTab: RootTab = .home
    @State private var homeScrollToTopRequest = 0
    @State private var searchScrollToTopRequest = 0
    @State private var seriesScrollToTopRequest = 0
    @State private var moviesScrollToTopRequest = 0

    init() {
        Self.configureTabBarAppearance()
    }

    var body: some View {
        ZStack {
            TabView(selection: selectedTabBinding) {
                HomeView(scrollToTopRequest: homeScrollToTopRequest)
                    .tabItem {
                        Label("Home", systemImage: "house")
                    }
                    .tag(RootTab.home)

                SearchView(scrollToTopRequest: searchScrollToTopRequest)
                    .tabItem {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    .tag(RootTab.search)

                SeriesView(scrollToTopRequest: seriesScrollToTopRequest)
                    .tabItem {
                        Label("Series", systemImage: "tv")
                    }
                    .tag(RootTab.series)

                MoviesView(scrollToTopRequest: moviesScrollToTopRequest)
                    .tabItem {
                        Label("Movies", systemImage: "film")
                    }
                    .tag(RootTab.movies)

                iPhoneMoreView()
                    .tabItem {
                        Label("More", systemImage: "ellipsis")
                    }
                    .tag(RootTab.more)
            }
            .ignoresSafeArea(.container, edges: .top)

            StreamPlayerPresenter(request: $playbackStore.request)
                .frame(width: 0, height: 0)
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear {
            updateOrientation(for: playbackStore.request?.id)
        }
        .onChange(of: playbackStore.request?.id) { _, requestID in
            updateOrientation(for: requestID)
        }
    }

    private static func configureTabBarAppearance() {
        let selectedColor = UIColor.systemBlue
        let normalColor = UIColor.white.withAlphaComponent(0.58)

        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .black
        appearance.shadowColor = UIColor.white.withAlphaComponent(0.12)

        configureTabBarItemAppearance(
            appearance.stackedLayoutAppearance,
            selectedColor: selectedColor,
            normalColor: normalColor
        )
        configureTabBarItemAppearance(
            appearance.inlineLayoutAppearance,
            selectedColor: selectedColor,
            normalColor: normalColor
        )
        configureTabBarItemAppearance(
            appearance.compactInlineLayoutAppearance,
            selectedColor: selectedColor,
            normalColor: normalColor
        )

        let tabBarAppearance = UITabBar.appearance()
        tabBarAppearance.standardAppearance = appearance
        tabBarAppearance.scrollEdgeAppearance = appearance
        tabBarAppearance.unselectedItemTintColor = normalColor
    }

    private static func configureTabBarItemAppearance(
        _ appearance: UITabBarItemAppearance,
        selectedColor: UIColor,
        normalColor: UIColor
    ) {
        appearance.selected.iconColor = selectedColor
        appearance.selected.titleTextAttributes = [.foregroundColor: selectedColor]
        appearance.normal.iconColor = normalColor
        appearance.normal.titleTextAttributes = [.foregroundColor: normalColor]
    }

    private var selectedTabBinding: Binding<RootTab> {
        Binding(
            get: { selectedTab },
            set: { newTab in
                if newTab == selectedTab {
                    requestScrollToTop(for: newTab)
                }

                selectedTab = newTab
            }
        )
    }

    private func requestScrollToTop(for tab: RootTab) {
        switch tab {
        case .home:
            homeScrollToTopRequest += 1
        case .search:
            searchScrollToTopRequest += 1
        case .series:
            seriesScrollToTopRequest += 1
        case .movies:
            moviesScrollToTopRequest += 1
        case .more:
            break
        }
    }

    private func updateOrientation(for requestID: StreamPlaybackRequest.ID?) {
        if requestID == nil {
            AppOrientationController.shared.lockToPortrait()
        } else {
            AppOrientationController.shared.lockToLandscape()
        }
    }
}

private enum RootTab: Hashable {
    case home
    case search
    case series
    case movies
    case more
}

private struct StreamPlayerPresenter: UIViewControllerRepresentable {
    @Binding var request: StreamPlaybackRequest?

    func makeCoordinator() -> Coordinator {
        Coordinator(request: $request)
    }

    func makeUIViewController(context: Context) -> StreamPlayerPresentationController {
        StreamPlayerPresentationController()
    }

    func updateUIViewController(
        _ uiViewController: StreamPlayerPresentationController,
        context: Context
    ) {
        uiViewController.update(request: request, coordinator: context.coordinator)
    }

    final class Coordinator {
        private var request: Binding<StreamPlaybackRequest?>

        init(request: Binding<StreamPlaybackRequest?>) {
            self.request = request
        }

        func closePlayer() {
            request.wrappedValue = nil
        }
    }
}

private final class StreamPlayerPresentationController: UIViewController {
    private var playerController: StreamPlayerHostingController?

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .portrait
    }

    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        .portrait
    }

    func update(request: StreamPlaybackRequest?, coordinator: StreamPlayerPresenter.Coordinator) {
        guard let request else {
            dismissPlayerIfNeeded()
            return
        }

        let onBack = { [weak self, weak coordinator] in
            self?.dismissPlayerIfNeeded()
            coordinator?.closePlayer()
        }

        if let playerController {
            guard playerController.requestID != request.id else {
                playerController.rootView = StreamPlayerView(request: request, onBack: onBack)
                return
            }

            playerController.rootView = StreamPlayerView(request: request, onBack: onBack)
            playerController.requestID = request.id
            return
        }

        let playerController = StreamPlayerHostingController(
            requestID: request.id,
            rootView: StreamPlayerView(request: request, onBack: onBack)
        )
        playerController.modalPresentationStyle = .fullScreen
        playerController.modalTransitionStyle = .crossDissolve
        self.playerController = playerController

        AppOrientationController.shared.lockToLandscape()
        present(playerController, animated: false)
    }

    private func dismissPlayerIfNeeded() {
        guard let playerController else {
            AppOrientationController.shared.lockToPortrait()
            return
        }

        self.playerController = nil
        playerController.dismiss(animated: false) {
            AppOrientationController.shared.lockToPortrait()
        }
    }
}

private final class StreamPlayerHostingController: UIHostingController<StreamPlayerView> {
    var requestID: StreamPlaybackRequest.ID

    init(requestID: StreamPlaybackRequest.ID, rootView: StreamPlayerView) {
        self.requestID = requestID
        super.init(rootView: rootView)
        modalPresentationCapturesStatusBarAppearance = true
    }

    @available(*, unavailable)
    @MainActor dynamic required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .landscapeRight
    }

    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        .landscapeRight
    }

    override var prefersStatusBarHidden: Bool {
        true
    }
}

private struct iPhoneMoreView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    moreLink(
                        title: "Collections",
                        systemImage: "square.stack.fill",
                        destination: CollectionsView(ownsNavigationStack: false)
                    )

                    Divider()
                        .overlay(Color.white.opacity(0.12))

                    moreLink(
                        title: "Addons",
                        systemImage: "puzzlepiece.extension.fill",
                        destination: AddonsView(ownsNavigationStack: false)
                    )
                }
                .padding(.horizontal, 16)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 12)
            }
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.inline)
            .interactivePopGestureEnabled()
        }
    }

    private func moreLink<Destination: View>(
        title: String,
        systemImage: String,
        destination: Destination
    ) -> some View {
        NavigationLink {
            destination
        } label: {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white.opacity(0.84))
                    .frame(width: 24)

                Text(title)
                    .font(.body)
                    .foregroundColor(.white)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.42))
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
#endif
