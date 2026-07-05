import SwiftUI

#if os(iOS)
import UIKit

struct iPhoneRootShell: View {
    @ObservedObject private var playbackStore = StreamPlaybackStore.shared
    @State private var selectedTab: RootTab = .home
    @State private var homeScrollToTopRequest = 0
    @State private var searchScrollToTopRequest = 0

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

                CollectionsView()
                    .tabItem {
                        Label("Collections", systemImage: "square.stack")
                    }
                    .tag(RootTab.collections)

                AddonsView()
                    .tabItem {
                        Label("Addons", systemImage: "puzzlepiece.extension")
                    }
                    .tag(RootTab.addons)

                SearchView(scrollToTopRequest: searchScrollToTopRequest)
                    .tabItem {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    .tag(RootTab.search)
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
        case .collections, .addons:
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
    case collections
    case addons
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

#endif
