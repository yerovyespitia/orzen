import SwiftUI

@MainActor
final class StreamPlayerChromeVisibilityController: ObservableObject {
    @Published private(set) var isVisible = true

    private var hideTask: Task<Void, Never>?

    func reveal() {
        if !isVisible {
            withAnimation(.easeInOut(duration: 0.18)) {
                isVisible = true
            }
        }
    }

    func keepVisible() {
        cancelAutoHide()
        reveal()
    }

    func hide() {
        hideTask?.cancel()
        hideTask = nil

        guard isVisible else { return }

        withAnimation(.easeInOut(duration: 0.18)) {
            isVisible = false
        }
    }

    func scheduleAutoHide(isAllowed: Bool) {
        hideTask?.cancel()

        guard isAllowed else { return }

        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard !Task.isCancelled else { return }

                withAnimation(.easeInOut(duration: 0.24)) {
                    self?.isVisible = false
                }
            }
        }
    }

    func cancelAutoHide() {
        hideTask?.cancel()
        hideTask = nil
    }

    deinit {
        hideTask?.cancel()
    }
}
