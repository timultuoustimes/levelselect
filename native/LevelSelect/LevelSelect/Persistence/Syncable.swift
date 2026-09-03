import Foundation

/// Shared sync metadata across the synced entities. Lets the repository bump
/// `updatedAt`/`revision` and set tombstones generically. (Profile,
/// SyncOperation, and MigrationReceipt are intentionally NOT Syncable —
/// Profile is identity, the other two are local bookkeeping.)
protocol Syncable: AnyObject {
    var id: UUID { get }
    var userID: UUID? { get set }
    var createdAt: Date { get }
    var updatedAt: Date { get set }
    var revision: Int { get set }
    var deletedAt: Date? { get set }
    var legacyID: String? { get set }
}

extension Game: Syncable {}
extension Playthrough: Syncable {}
extension Session: Syncable {}
extension CompletionEvent: Syncable {}
extension TrackerSchemaRecord: Syncable {}
extension TrackerStateRecord: Syncable {}
extension Run: Syncable {}
extension GameMap: Syncable {}
extension Marker: Syncable {}
extension Memory: Syncable {}
extension GameVideo: Syncable {}
extension GameCollection: Syncable {}
extension TrackerItemDetail: Syncable {}
extension EarnedBadge: Syncable {}
