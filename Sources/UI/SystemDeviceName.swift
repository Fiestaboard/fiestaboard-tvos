import UIKit

/// The device's own name, as tvOS reports it to this app.
///
/// Without the `com.apple.developer.device-information.user-assigned-device-name`
/// entitlement (O6, owner-pending; it lands in its own PR after O6 — review
/// r2 C3), `UIDevice.current.name` is the model name, which
/// `DeviceName.choose` treats as the DD3 fallback.
enum SystemDeviceName {
    @MainActor static var current: DeviceNameChoice {
        DeviceName.choose(system: UIDevice.current.name, model: UIDevice.current.model)
    }
}
