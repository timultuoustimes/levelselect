import Foundation

/// Someone you played with.
///
/// Two names, either optional, because co-op happens across a couch and a
/// voice channel at once: the person is "Rosalie", the handle is who they are
/// on the Switch, and which one you'd write down depends on the game. Insisting
/// on one would make the other unrecordable.
///
/// Deliberately NOT a stored model with a relationship. A `Companion` record
/// would be a contact list, and a contact list is the first half of a social
/// graph — which this app has said it isn't building. These are strings
/// attached to a moment, not people the app knows.
struct Companion: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    /// What you call them.
    var name: String = ""
    /// What they're called on the platform — gamertag, PSN id, username.
    var handle: String = ""

    var isEmpty: Bool {
        name.trimmingCharacters(in: .whitespaces).isEmpty
            && handle.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// "Rosalie", "@umigame", or "Rosalie (@umigame)" — whichever it has.
    var display: String {
        let n = name.trimmingCharacters(in: .whitespaces)
        let h = handle.trimmingCharacters(in: .whitespaces)
        switch (n.isEmpty, h.isEmpty) {
        case (false, false): return "\(n) (\(h))"
        case (false, true):  return n
        case (true, false):  return h
        case (true, true):   return ""
        }
    }
}

extension Array where Element == Companion {
    /// Stored as JSON in a `Data` column, the same way video parts and status
    /// colours already are — one additive field per model instead of a table.
    var encoded: Data? {
        let kept = filter { !$0.isEmpty }
        guard !kept.isEmpty else { return nil }
        return try? JSONEncoder().encode(kept)
    }

    static func decoded(_ data: Data?) -> [Companion] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([Companion].self, from: data)) ?? []
    }

    /// "Rosalie and Kenny", "Rosalie, Kenny and Cate" — read aloud, not a
    /// comma-joined list, because these are people.
    var sentence: String {
        let names = compactMap { $0.display.isEmpty ? nil : $0.display }
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
        }
    }
}
