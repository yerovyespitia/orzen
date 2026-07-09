import SwiftUI
#if os(iOS)
import UIKit
#endif

@main
struct OrzenApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(OrzenAppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            ContentView()
                .frame(minWidth: 1280, minHeight: 780)
                .task {
                    await LaunchCatalogPrefetcher.prefetchInitialCatalogs()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
        #else
        WindowGroup {
            ContentView()
                .task {
                    await LaunchCatalogPrefetcher.prefetchInitialCatalogs()
                }
        }
        #endif
    }
}

#if os(iOS)
final class OrzenAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        AppOrientationController.shared.supportedOrientations
    }
}

final class AppOrientationController {
    static let shared = AppOrientationController()

    private(set) var supportedOrientations: UIInterfaceOrientationMask = .portrait

    private init() {}

    func lockToPortrait() {
        updateSupportedOrientations(.portrait, preferredOrientation: .portrait)
    }

    func lockToLandscape() {
        updateSupportedOrientations(.landscapeRight, preferredOrientation: .landscapeRight)
    }

    func allowPlayerPresentation() {
        supportedOrientations = [.portrait, .landscapeRight]
    }

    private func updateSupportedOrientations(
        _ orientations: UIInterfaceOrientationMask,
        preferredOrientation: UIInterfaceOrientation
    ) {
        supportedOrientations = orientations

        if #available(iOS 16.0, *) {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .forEach { windowScene in
                    windowScene.windows
                        .first?
                        .rootViewController?
                        .setNeedsUpdateOfSupportedInterfaceOrientations()
                    windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations)) { error in
                        print("Failed to update orientation: \(error.localizedDescription)")
                    }
                }
        } else {
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }
}
#endif

private enum LaunchCatalogPrefetcher {
    @MainActor
    static func prefetchInitialCatalogs() async {
        async let home: Void = HomeCatalogStore.shared.prefetchIfNeeded()
        async let moviesAndSeries: Void = CinemetaCatalogPresets.prefetchInitialCatalogs()

        _ = await (home, moviesAndSeries)
    }
}
