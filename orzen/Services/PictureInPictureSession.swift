import Combine
import Foundation

final class PictureInPictureSession: ObservableObject {
    @Published private(set) var isPossible = false
    @Published private(set) var isActive = false

    private var registrationID: UUID?
    private var startAction: (() -> Void)?
    private var stopAction: (() -> Void)?

    var isAvailable: Bool {
        isPossible || isActive
    }

    func attach(
        registrationID: UUID,
        isPossible: Bool,
        isActive: Bool,
        start: @escaping () -> Void,
        stop: @escaping () -> Void
    ) {
        self.registrationID = registrationID
        self.isPossible = isPossible
        self.isActive = isActive
        startAction = start
        stopAction = stop
    }

    func update(registrationID: UUID, isPossible: Bool, isActive: Bool) {
        guard self.registrationID == registrationID else { return }
        self.isPossible = isPossible
        self.isActive = isActive
    }

    func detach(registrationID: UUID) {
        guard self.registrationID == registrationID else { return }
        self.registrationID = nil
        isPossible = false
        isActive = false
        startAction = nil
        stopAction = nil
    }

    func toggle() {
        if isActive {
            stopAction?()
        } else if isPossible {
            startAction?()
        }
    }
}
