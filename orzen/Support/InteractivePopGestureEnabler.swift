import SwiftUI

#if os(iOS)
import UIKit

extension View {
    func interactivePopGestureEnabled() -> some View {
        background(InteractivePopGestureEnabler())
    }

    func popNavigationToRoot(on request: Int) -> some View {
        background(NavigationRootPopper(request: request))
    }
}

private struct InteractivePopGestureEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.enableInteractivePopGesture()
    }

    final class Controller: UIViewController {
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            enableInteractivePopGesture()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            enableInteractivePopGesture()
        }

        func enableInteractivePopGesture() {
            guard let gesture = navigationController?.interactivePopGestureRecognizer else { return }

            gesture.isEnabled = true
            gesture.delegate = nil
        }
    }
}

private struct NavigationRootPopper: UIViewControllerRepresentable {
    let request: Int

    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.popToRootIfNeeded(for: request)
    }

    final class Controller: UIViewController {
        private var lastHandledRequest = 0

        func popToRootIfNeeded(for request: Int) {
            guard request != lastHandledRequest else { return }
            lastHandledRequest = request
            navigationController?.popToRootViewController(animated: true)
        }
    }
}
#endif
