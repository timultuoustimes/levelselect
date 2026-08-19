import Foundation

/// A device-local note of which playthrough each session it created belongs to.
///
/// Sessions have been losing their playthrough — not at save time (a guard
/// proved that, and two experiments ruled out ordinary and offline use), but
/// somewhere after it, during two-device activity. Whatever CloudKit is doing
/// to that reference, the fact itself is not in doubt on the device that
/// created the record: it knew the answer at the moment it wrote it.
///
/// So it writes the answer down. This is NOT an inference — the whole reason
/// detached sessions couldn't be recovered automatically is that nothing in
/// the store said where they belonged, and guessing was refused. A note taken
/// at creation is a record, not a guess, which is what makes repairing from it
/// legitimate where re-parenting by heuristic would not be.
///
/// Deliberately local and unsynced: it describes what THIS device did, it must
/// survive the merge that loses the relationship (so it cannot live in the
/// synced store), and a device that didn't create a session has nothing
/// truthful to say about it. Bounded, because it is a repair aid and not
/// history.
enum SessionParentLedger {
    private static let key = "sessionParentLedger"
    private static let limit = 500

    private static var entries: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// Record the parent of a session this device just created.
    static func record(sessionID: UUID, playthroughID: UUID) {
        var all = entries
        all[sessionID.uuidString] = playthroughID.uuidString
        if all.count > limit {
            // Oldest-out is unavailable without timestamps, and adding them
            // would double the size for a cache whose worst failure is
            // forgetting how to repair one old session. Drop an arbitrary
            // slice instead, keeping the most recently written key.
            let keep = Array(all.keys.shuffled().prefix(limit - 1))
            var trimmed = [String: String]()
            for id in keep { trimmed[id] = all[id] }
            trimmed[sessionID.uuidString] = playthroughID.uuidString
            all = trimmed
        }
        entries = all
    }

    static func playthroughID(for sessionID: UUID) -> UUID? {
        entries[sessionID.uuidString].flatMap(UUID.init(uuidString:))
    }

    static func forget(sessionID: UUID) {
        var all = entries
        all.removeValue(forKey: sessionID.uuidString)
        entries = all
    }
}
