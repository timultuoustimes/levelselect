import Foundation
import SwiftData

/// The signed-in user. With CloudKit the account is implicit (iCloud), so this
/// is mostly a convenience record. CloudKit-compatible.
@Model
final class Profile {
    var id: UUID = UUID()
    var appleUserIdentifier: String = ""
    var email: String?
    var displayName: String?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(
        id: UUID = UUID(),
        appleUserIdentifier: String = "",
        email: String? = nil,
        displayName: String? = nil
    ) {
        self.id = id
        self.appleUserIdentifier = appleUserIdentifier
        self.email = email
        self.displayName = displayName
    }
}
