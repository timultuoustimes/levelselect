import Foundation
// Both, where both exist: watchOS imports UIKit too, so an `#elseif` chain
// here silently skipped WatchKit and left WKInterfaceDevice undefined.
#if canImport(WatchKit)
import WatchKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// What this device calls itself, stamped onto sessions it starts.
///
/// The name is USER-SETTABLE and stored per device, which is deliberate on
/// both counts.
///
/// Per device, in `UserDefaults`: a device's own name is the one setting that
/// genuinely should not sync — every device needs a different answer. (This is
/// the opposite of the Deku wishlist URL, which lived in UserDefaults, needed
/// to sync, and therefore never did.)
///
/// User-settable, because the system will not tell us. Since iOS 16 an app
/// asking for the device name gets the MODEL back — "iPhone", "iPad" — not
/// what the user named it, unless it holds an entitlement Apple grants by
/// request. Two iPads both reporting "iPad" is exactly no help in a prompt
/// whose whole purpose is telling two devices apart, so the user gets to name
/// it, defaulting to the model so the field is never empty.
enum DeviceIdentity {
    private static let key = "deviceDisplayName"

    /// The system's answer — the model on modern iOS, the host name on Mac.
    static var systemDefaultName: String {
        #if os(macOS)
        let host = Host.current().localizedName
        return (host?.isEmpty == false ? host! : "Mac")
        #elseif canImport(WatchKit)
        return WKInterfaceDevice.current().name
        #elseif canImport(UIKit)
        return UIDevice.current.name
        #else
        return "This device"
        #endif
    }

    /// What sessions started here are stamped with. Trimmed; falls back to the
    /// system name when unset or blanked.
    static var name: String {
        get {
            let stored = (UserDefaults.standard.string(forKey: key) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return stored.isEmpty ? systemDefaultName : stored
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                UserDefaults.standard.removeObject(forKey: key)
            } else {
                UserDefaults.standard.set(trimmed, forKey: key)
            }
        }
    }

    /// Whether the user has chosen a name rather than inheriting the model.
    static var hasCustomName: Bool {
        !((UserDefaults.standard.string(forKey: key) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty)
    }
}
