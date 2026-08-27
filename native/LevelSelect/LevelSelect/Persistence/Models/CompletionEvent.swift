import Foundation
import SwiftData

/// A completion moment (legacy `clears[]` + status transitions). CloudKit-compatible.
@Model
final class CompletionEvent {
    var id: UUID = UUID()
    var userID: UUID?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var revision: Int = 0
    var deletedAt: Date?
    var legacyID: String?

    var date: Date = Date.now
    var label: CompletionLabel = CompletionLabel.cleared
    var customLabel: String?   // used when label == .custom
    var platform: String?
    var notes: String?
    /// Who you played it with. See `Companion` — names and handles, stored as
    /// JSON rather than a table, because these are strings attached to a
    /// moment and not people the app knows.
    var playedWithData: Data?
    /// How much of `date` is real: nil/"day" = the whole thing, "month" =
    /// month+year, "year" = year only. "I beat Skyrim the year it came out"
    /// is a true statement with a year in it — storing it as January 1st and
    /// PRINTING January 1st would turn a truth into a lie. Additive optional,
    /// so records from before this field simply read as exact days (which
    /// they were).
    var datePrecision: String?
    /// When the playthrough this finish caps BEGAN, with its own fuzzy
    /// precision (same vocabulary as `datePrecision`). Optional twice over:
    /// nil means "not recorded", which most historical finishes are. A span —
    /// "Dec 2025 → Jan 2026" — is the diary sentence people actually want;
    /// a finish alone is a timestamp, a span is a memory. Additive optionals,
    /// promoted with the build-31 batch.
    var startedDate: Date?
    var startedPrecision: String?

    var game: Game?
    /// The run this moment capped, when there was one. Optional on purpose:
    /// a 2011 clear logged from memory belongs to the game, not to any
    /// playthrough the app ever saw. "Finished" on a playthrough is DERIVED
    /// from these — a live beaten event pointing at it — never stored as a
    /// second flag that could disagree.
    var playthrough: Playthrough?

    init(
        id: UUID = UUID(),
        date: Date = .now,
        label: CompletionLabel = .cleared,
        customLabel: String? = nil
    ) {
        self.id = id
        self.createdAt = .now
        self.updatedAt = .now
        self.date = date
        self.label = label
        self.customLabel = customLabel
    }
}

/// `sheet(item:)` needs it; the id is already there.
extension CompletionEvent: Identifiable {}

extension CompletionEvent {
    var companions: [Companion] {
        get { [Companion].decoded(playedWithData) }
        set { playedWithData = newValue.encoded }
    }

    /// The date, said only as precisely as it's known.
    var dateText: String {
        Self.fuzzyText(date, precision: datePrecision)
    }

    /// The span, when a start was recorded: "Dec 2025 → Jan 2026". Without
    /// one it's just the finish — never an invented start. Months abbreviate
    /// inside a span (two wide months crowd a row); alone they stay wide.
    var spanText: String {
        guard let startedDate else { return dateText }
        let start = Self.fuzzyText(startedDate, precision: startedPrecision, wideMonth: false)
        let end = Self.fuzzyText(date, precision: datePrecision, wideMonth: false)
        // "Jan 2026 → Jan 2026" says less than "Jan 2026" does.
        guard start != end else { return dateText }
        return "\(start) → \(end)"
    }

    static func fuzzyText(_ date: Date, precision: String?, wideMonth: Bool = true) -> String {
        switch precision {
        case "year":
            return String(Calendar.current.component(.year, from: date))
        case "month":
            return date.formatted(.dateTime.month(wideMonth ? .wide : .abbreviated).year())
        default:
            return date.formatted(date: .abbreviated, time: .omitted)
        }
    }

    var labelText: String {
        label == .custom ? (customLabel?.isEmpty == false ? customLabel! : "Completed")
                         : label.display
    }
}

extension CompletionLabel {
    /// Two of these carry the app's philosophy: "Beat the game" is rolling
    /// credits, and "100%" is finishing every item on YOUR list — which may
    /// be trimmed, curated, personal. Neither claims a platinum; external
    /// validations (RA mastery, PSN platinum) stay their own kinds.
    var display: String {
        switch self {
        case .cleared:        "Beat the game"
        case .hundredPercent: "100%"
        case .newGamePlus:    "New Game+"
        case .completed:      "Completed"
        case .custom:         "Custom"
        }
    }
}
