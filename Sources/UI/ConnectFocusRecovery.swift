import Foundation

/// A failed activated control may recover its lost native focus once. A
/// newer real owner cancels that debt; nil alone is the observed layout loss.
struct ConnectFocusRecovery<Target: Equatable> {
    private var attempt: (token: UUID, target: Target)?

    mutating func begin(target: Target, focused: Target?) -> UUID {
        let token = UUID()
        attempt = focused == target ? (token, target) : nil
        return token
    }

    mutating func focusChanged(to focused: Target?) {
        guard let focused, let attempt else { return }
        if focused != attempt.target { self.attempt = nil }
    }

    func target(for token: UUID) -> Target? {
        guard attempt?.token == token else { return nil }
        return attempt?.target
    }

    mutating func finish(token: UUID, failed: Bool, focused: Target?, available: Bool) -> Target? {
        guard let request = attempt, request.token == token else { return nil }
        attempt = nil
        guard failed, available, focused == nil || focused == request.target else { return nil }
        return request.target
    }

    mutating func cancel() { attempt = nil }
}
