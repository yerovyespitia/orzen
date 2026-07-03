import SwiftUI

#if os(iOS)
import UIKit

extension View {
    func interactivePopGestureEnabled() -> some View {
        background(InteractivePopGestureEnabler())
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
#endif
