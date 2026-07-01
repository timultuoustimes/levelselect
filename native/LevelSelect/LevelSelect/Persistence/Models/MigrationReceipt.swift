import Foundation
import SwiftData

/// Idempotency record for the one-time legacy import. A second import of the
/// same source device is a no-op.
@Model
final class MigrationReceipt {
    @Attribute(.unique) var id: UUID
    var sourceDeviceID: String
    var importedAt: Date
    var appVersion: String
    var countsJSON: Data

    init(
        id: UUID = UUID(),
        sourceDeviceID: String,
        appVersion: String,
        countsJSON: Data = Data()
    ) {
        self.id = id
        self.sourceDeviceID = sourceDeviceID
        self.importedAt = .now
        self.appVersion = appVersion
        self.countsJSON = countsJSON
    }
}
