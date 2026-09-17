import Foundation

/// A service's achievement or trophy list, shaped as an installable tracker
/// schema — what PlayStation and Xbox imports hand to `applyGeneratedSchema`.
struct ImportedSet: Sendable {
    let title: String
    let count: Int
    let schema: Data
}

/// What an account has earned in one game. Unlocks are `RAUnlock`s because the
/// fold into a tracker is the same for every service: union, never subtraction.
struct ServiceProgress: Sendable {
    let total: Int
    let unlocked: [RAUnlock]
}

enum ServiceDates {
    /// ISO 8601 as the services write it. Xbox sends seven fractional digits,
    /// which `ISO8601DateFormatter` refuses, so the fraction is cut to three.
    /// Xbox's "0001-01-01…" means never, and reads as nil.
    static func parse(_ text: String?) -> Date? {
        guard var text, !text.isEmpty, !text.hasPrefix("0001") else { return nil }
        if let dot = text.firstIndex(of: ".") {
            let digits = text[text.index(after: dot)...].prefix { $0.isNumber }
            if digits.count > 3 {
                let tailStart = text.index(text.index(after: dot), offsetBy: digits.count)
                text = String(text[..<text.index(after: dot)]) + String(digits.prefix(3)) + String(text[tailStart...])
            }
        }
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: text) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }
}

enum ServiceNames {
    /// The same game under two spellings — "Marvel's Spider-Man 2™" and
    /// "Marvel’s Spider-Man 2". Letters and numbers only, case-folded. Exact on
    /// what's left, because this decides where playtime goes.
    static func same(_ a: String, _ b: String) -> Bool {
        let x = fold(a), y = fold(b)
        return !x.isEmpty && x == y
    }

    static func fold(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
