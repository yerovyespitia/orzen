#if os(iOS)
import SwiftUI
import UIKit

struct VLCPlayerView: UIViewRepresentable {
    @ObservedObject var controller: VLCPlaybackController

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        view.isUserInteractionEnabled = false
        controller.drawable = view
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if controller.drawable == nil {
            controller.drawable = uiView
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: ()) {
    }
}
#endif
