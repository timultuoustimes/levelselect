import Foundation

/// **A slice of imported time, and the years the person says it belongs to.**
///
/// Steam, PlayStation and Xbox report one lifetime total and no dates, so
/// those hours sit outside every dated view in the app. The one thing the
/// person knows that the API doesn't is roughly *when* — Tim, 09-21: *"I know
/// I played cities skylines the most in 2020-2021… I guess I played more
/// around 2021-2023, because I had stopped around the release date of cities
/// skylines 2."*
///
/// That quote is also the argument against dividing a total evenly across a
/// range: he stopped in October, so the last year of his own range is a part
/// year and lighter than the ones before it. An even split would state three
/// numbers nobody supplied, and they would then be indistinguishable from
/// time that was actually measured.
///
/// So a span is **attribution, not arithmetic**:
///
/// - One span over `2021...2023` appears on each of those three years, named
///   as the whole span, and is added to none of their totals.
/// - Three spans of one year each say what you actually believe, year by
///   year, and each lands in its own year.
///
/// The authority on how much time there is remains
/// `Playthrough.carriedOverSeconds`. Spans only describe how it is spread, so
/// every existing reading of the total stays correct whether spans exist or
/// not, and a span list that disagrees with the total is a display problem
/// rather than a wrong number.
struct CarriedOverSpan: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var seconds: TimeInterval
    /// First year this covers.
    var fromYear: Int
    /// Last year, inclusive. Equal to `fromYear` for a single year.
    var toYear: Int

    init(id: UUID = UUID(), seconds: TimeInterval, fromYear: Int, toYear: Int? = nil) {
        self.id = id
        self.seconds = max(0, seconds)
        let first = min(fromYear, toYear ?? fromYear)
        let last = max(fromYear, toYear ?? fromYear)
        self.fromYear = first
        self.toYear = last
    }

    var isSingleYear: Bool { fromYear == toYear }
    var years: ClosedRange<Int> { fromYear...toYear }
    func covers(_ year: Int) -> Bool { years.contains(year) }

    /// "2022" or "2021–2023" — an en dash, because it is a range of years and
    /// not a subtraction.
    var label: String {
        isSingleYear ? "\(fromYear)" : "\(fromYear)–\(toYear)"
    }
}

extension Array where Element == CarriedOverSpan {
    /// Every span touching a year, in the order they were entered.
    func covering(_ year: Int) -> [CarriedOverSpan] { filter { $0.covers(year) } }

    var totalSeconds: TimeInterval { reduce(0) { $0 + $1.seconds } }

    static func decoded(_ data: Data?) -> [CarriedOverSpan] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([CarriedOverSpan].self, from: data)) ?? []
    }

    /// Nil rather than an empty array's bytes, so a playthrough with no spans
    /// writes no value and an old build reading it sees exactly what it saw
    /// before.
    var encoded: Data? {
        isEmpty ? nil : try? JSONEncoder().encode(self)
    }
}
