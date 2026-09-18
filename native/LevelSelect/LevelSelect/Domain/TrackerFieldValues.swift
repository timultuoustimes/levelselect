import Foundation

/// What a playthrough has recorded against one tracker item beyond its
/// checkbox: a unit's class and level, whether it's in the party, and the
/// item's status (in progress, failed, fallen…).
///
/// Stored as JSON in `TrackerStateRecord.valuesJSON`, one entry per field,
/// **each with its own time**. Two devices that edit different fields of the
/// same unit both keep their edit, and a later clear beats an older value —
/// the rule `selectedVariantUpdatedAt` set for the one field it covers. A
/// whole-blob last-writer-wins would lose one device's class change to the
/// other's level change, which is the conflict Codex warned about on 08-20.
///
/// Declarations (which fields a category has) live in the tracker blob; see
/// `TrackerFieldDTO`. Values for fields a category no longer declares are
/// kept, not dropped: removing a field and adding it back finds the values.
struct TrackerFieldValues: Equatable, Sendable {
    enum Value: Equatable, Sendable {
        case text(String)
        case number(Double)
        case toggle(Bool)
        /// Deliberately cleared. Kept as an entry so its time can beat an
        /// older value on another device.
        case cleared
    }

    struct Entry: Equatable, Sendable {
        var value: Value
        var at: Date
    }

    /// The reserved key status rides under. Field ids come from tracker JSON,
    /// which never starts an id with an underscore.
    static let statusKey = "_status"
    /// Where a fallen unit fell — "Chapter 12". Reserved like `_status`.
    static let fellInKey = "_fellIn"

    var entries: [String: Entry] = [:]

    init(entries: [String: Entry] = [:]) {
        self.entries = entries
    }

    // MARK: Reading

    func value(_ fieldID: String) -> Value? {
        guard let entry = entries[fieldID], entry.value != .cleared else { return nil }
        return entry.value
    }

    func text(_ fieldID: String) -> String? {
        switch value(fieldID) {
        case .text(let s): s.isEmpty ? nil : s
        case .number(let n): Self.format(n)
        case .toggle, .cleared, nil: nil
        }
    }

    func number(_ fieldID: String) -> Double? {
        if case .number(let n) = value(fieldID) { return n }
        return nil
    }

    func toggle(_ fieldID: String) -> Bool {
        if case .toggle(let b) = value(fieldID) { return b }
        return false
    }

    var status: TrackerItemStatus? {
        text(Self.statusKey).flatMap(TrackerItemStatus.init(rawValue:))
    }

    /// Anything recorded at all — what a removal must not take without asking.
    var hasContent: Bool { entries.values.contains { $0.value != .cleared } }

    static func format(_ n: Double) -> String {
        n.rounded() == n && abs(n) < 1e15 ? String(Int(n)) : String(n)
    }

    // MARK: Writing

    mutating func set(_ fieldID: String, _ value: Value?, at date: Date = .now) {
        entries[fieldID] = Entry(value: value ?? .cleared, at: date)
    }

    mutating func setStatus(_ status: TrackerItemStatus?, at date: Date = .now) {
        set(Self.statusKey, status.map { .text($0.rawValue) }, at: date)
    }

    /// Field by field, the newer entry wins; a tie keeps `self`, so folding the
    /// same rows in the same order always gives the same answer.
    func merged(with other: TrackerFieldValues) -> TrackerFieldValues {
        var out = self
        for (key, theirs) in other.entries {
            if let mine = out.entries[key], mine.at >= theirs.at { continue }
            out.entries[key] = theirs
        }
        return out
    }

    // MARK: JSON

    init(json: String?) {
        guard let data = json?.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return }
        for (key, raw) in root {
            guard let dict = raw as? [String: Any],
                  let stamp = (dict["at"] as? String).flatMap(Self.parseDate) else { continue }
            let value: Value
            switch dict["v"] {
            case let b as Bool where Self.isBool(dict["v"]): value = .toggle(b)
            case let n as NSNumber: value = .number(n.doubleValue)
            case let s as String: value = .text(s)
            default: value = .cleared
            }
            entries[key] = Entry(value: value, at: stamp)
        }
    }

    /// Nil when there is nothing to store, so an untouched row keeps a nil
    /// column rather than "{}".
    var json: String? {
        guard !entries.isEmpty else { return nil }
        var root: [String: Any] = [:]
        for (key, entry) in entries {
            var dict: [String: Any] = ["at": Self.formatDate(entry.at)]
            switch entry.value {
            case .text(let s): dict["v"] = s
            case .number(let n): dict["v"] = n
            case .toggle(let b): dict["v"] = b
            case .cleared: dict["v"] = NSNull()
            }
            root[key] = dict
        }
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// JSONSerialization hands back NSNumber for both booleans and numbers.
    private static func isBool(_ any: Any?) -> Bool {
        guard let n = any as? NSNumber else { return false }
        return CFGetTypeID(n) == CFBooleanGetTypeID()
    }

    private static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }

    private static func formatDate(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: d)
    }
}

/// Where an item stands beyond done / not done. Nil is the ordinary case.
///
/// `completed` stays the checkbox and the only thing progress counts. Failed
/// and missed items stay in the total — the game had them and you didn't get
/// them — which keeps a missed recruit visible rather than quietly shrinking
/// the list.
enum TrackerItemStatus: String, CaseIterable, Sendable {
    case inProgress, failed, missed, skipped, fallen

    var label: String {
        switch self {
        case .inProgress: "In progress"
        case .failed: "Failed"
        case .missed: "Missed"
        case .skipped: "Skipped"
        case .fallen: "Fallen"
        }
    }

    var systemImage: String {
        switch self {
        case .inProgress: "circle.lefthalf.filled"
        case .failed: "xmark.circle"
        case .missed: "clock.badge.xmark"
        case .skipped: "forward"
        case .fallen: "heart.slash"
        }
    }

    /// Fallen is a roster state; the others are for anything with a checkbox.
    static let general: [TrackerItemStatus] = [.inProgress, .failed, .missed, .skipped]
}
