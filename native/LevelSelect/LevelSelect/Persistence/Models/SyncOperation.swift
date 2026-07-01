import Foundation
import SwiftData

/// Outbox entry (local-only, not synced). Drives retry-with-backoff upserts
/// to Supabase; acknowledged ops are removed.
@Model
final class SyncOperation {
    @Attribute(.unique) var id: UUID
    var entityType: String
    var entityID: UUID
    var opType: SyncOpType
    var payloadJSON: Data?
    var attempts: Int
    var lastError: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        entityType: String,
        entityID: UUID,
        opType: SyncOpType,
        payloadJSON: Data? = nil
    ) {
        self.id = id
        self.entityType = entityType
        self.entityID = entityID
        self.opType = opType
        self.payloadJSON = payloadJSON
        self.attempts = 0
        self.lastError = nil
        self.createdAt = .now
    }
}
