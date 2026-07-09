import SwiftUI

#if os(iOS)
import UIKit

struct iPhoneRootShell: View {
    @ObservedObject private var playbackStore = StreamPlaybackStore.shared
    @State private var selectedTab: RootTab = .home
    @State private var homeScrollToTopRequest = 0
    @State private var searchScrollToTopRequest = 0
    @State private var homePopToRootRequest = 0
    @State private var collectionsPopToRootRequest = 0
    @State private var addonsPopToRootRequest = 0
    @State private var searchPopToRootRequest = 0
    @State private var searchText = ""
    @State private var searchActivationRequest = 0

    init() {
        if #unavailable(iOS 26) {
            Self.configureTabBarAppearance()
        }
    }

    var body: some View {
        ZStack {
            TabView(selection: selectedTabBinding) {
                Tab("Home", systemImage: "house", value: RootTab.home) {
                    HomeView(
                        scrollToTopRequest: homeScrollToTopRequest,
                        popToRootRequest: homePopToRootRequest
                    )
                }

                Tab("Collections", systemImage: "square.stack", value: RootTab.collections) {
                    CollectionsView(popToRootRequest: collectionsPopToRootRequest)
                }

                Tab("Addons", systemImage: "puzzlepiece.extension", value: RootTab.addons) {
                    AddonsView(popToRootRequest: addonsPopToRootRequest)
                }

                Tab(value: RootTab.search, role: .search) {
                    SearchView(
                        scrollToTopRequest: searchScrollToTopRequest,
                        popToRootRequest: searchPopToRootRequest,
                        searchText: $searchText,
                        showsSearchBar: false,
                        systemSearchActivationRequest: searchActivationRequest
                    )
                }
            }
            .tabViewSearchActivation(.searchTabSelection)
            .ignoresSafeArea(.container, edges: .top)

            StreamPlayerPresenter(request: $playbackStore.request)
                .frame(width: 0, height: 0)
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
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
                    handleTabReselection(for: newTab)
                }

                selectedTab = newTab

                if newTab == .search {
                    searchActivationRequest += 1
                }
            }
        )
    }

    private func handleTabReselection(for tab: RootTab) {
        switch tab {
        case .home:
            homePopToRootRequest += 1
            homeScrollToTopRequest += 1
        case .collections:
            collectionsPopToRootRequest += 1
        case .addons:
            addonsPopToRootRequest += 1
        case .search:
            searchPopToRootRequest += 1
            searchScrollToTopRequest += 1
            searchActivationRequest += 1
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

        AppOrientationController.shared.allowPlayerPresentation()
        present(playerController, animated: false) {
            AppOrientationController.shared.lockToLandscape()
        }
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
