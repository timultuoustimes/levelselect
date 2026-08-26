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
    /// How much of `date` is real: nil/"day" = the whole thing, "month" =
    /// month+year, "year" = year only. "I beat Skyrim the year it came out"
    /// is a true statement with a year in it — storing it as January 1st and
    /// PRINTING January 1st would turn a truth into a lie. Additive optional,
    /// so records from before this field simply read as exact days (which
    /// they were).
    var datePrecision: String?

    var game: Game?

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

extension CompletionEvent {
    /// The date, said only as precisely as it's known.
    var dateText: String {
        switch datePrecision {
        case "year":
            return String(Calendar.current.component(.year, from: date))
        case "month":
            return date.formatted(.dateTime.month(.wide).year())
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
