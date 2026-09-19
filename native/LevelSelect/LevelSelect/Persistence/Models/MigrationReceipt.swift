import Foundation
import SwiftData

/// Idempotency record for the one-time legacy import. Syncs via CloudKit so a
/// second device won't re-import. CloudKit-compatible.
@Model
final class MigrationReceipt {
    var id: UUID = UUID()
    var sourceDeviceID: String = ""
    var importedAt: Date = Date.now
    var appVersion: String = ""
    var countsJSON: Data = Data()

    init(
        id: UUID = UUID(),
        sourceDeviceID: String,
        appVersion: String,
        countsJSON: Data = Data()
    ) {
        self.id = id
        self.sourceDeviceID = sourceDeviceID
        self.appVersion = appVersion
        self.countsJSON = countsJSON
    }
}
