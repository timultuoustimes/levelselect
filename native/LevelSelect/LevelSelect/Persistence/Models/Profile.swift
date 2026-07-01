import Foundation
import SwiftData

/// The signed-in user (one row locally). `id` = Supabase auth.uid().
@Model
final class Profile {
    @Attribute(.unique) var id: UUID
    var appleUserIdentifier: String
    var email: String?
    var displayName: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        appleUserIdentifier: String,
        email: String? = nil,
        displayName: String? = nil
    ) {
        self.id = id
        self.appleUserIdentifier = appleUserIdentifier
        self.email = email
        self.displayName = displayName
        self.createdAt = .now
        self.updatedAt = .now
    }
}
