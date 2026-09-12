import Foundation
import OSLog

/// What's New and What's Coming, read from the site the app already has.
///
/// Both screens used to be rows that opened Safari. Tim: *"I think that the
/// 'what's new' is great to have, but there should be a 'what's coming'.
/// Being able to inform people ... all from within the app."*
///
/// **Nothing new had to be written to make this work.** The changelog is a
/// content collection with structured frontmatter that already builds a page
/// and an RSS feed; the roadmap is already a Now / Next / Exploring board with
/// a Shipped column. Two endpoints serve those same sources as JSON, so a
/// roadmap reviewed on the site is a roadmap the app agrees with — no second
/// list to keep in step, and no way for one to quietly go stale.
///
/// **These are reads, not reports.** Fetching a public JSON file sends nothing
/// about the person doing it: no install id, no query, no headers of ours. The
/// edge-function headers (`x-ls-app-key`, `x-ls-install`) are deliberately NOT
/// applied here — they exist to scope quotas on endpoints that cost money, and
/// a static file on the marketing site is not one.
enum NewsFeeds {
    static let changelogURL = URL(string: "https://levelselect.app/changelog/feed.json")!
    static let roadmapURL = URL(string: "https://levelselect.app/roadmap/feed.json")!

    private static let log = Logger(subsystem: Diagnostics.subsystem, category: "news")

    // MARK: Shapes

    struct Changelog: Codable, Sendable {
        var releases: [Release]

        struct Release: Codable, Sendable, Identifiable {
            var id: String
            var version: String
            var build: Int?
            var date: Date
            var title: String
            var summary: String
            var items: [Item]
            var url: URL?
        }

        struct Item: Codable, Sendable, Identifiable, Hashable {
            var title: String
            var kind: Kind
            var detail: String
            var id: String { title + detail }
        }

        /// Unknown kinds decode as `.new` rather than failing the whole feed —
        /// a tag added on the site should never blank out this screen in a
        /// version of the app that shipped before it.
        enum Kind: String, Codable, Sendable {
            case new, improved, fixed

            init(from decoder: Decoder) throws {
                let raw = try decoder.singleValueContainer().decode(String.self)
                self = Kind(rawValue: raw) ?? .new
            }

            var label: String {
                switch self {
                case .new:      "New"
                case .improved: "Improved"
                case .fixed:    "Fixed"
                }
            }
            var icon: String {
                switch self {
                case .new:      "sparkles"
                case .improved: "wand.and.sparkles"
                case .fixed:    "wrench.adjustable"
                }
            }
        }
    }

    struct Roadmap: Codable, Sendable {
        var reviewed: String
        var disclaimer: String
        var horizons: [Horizon]
        var shipped: [Shipped]
        var notPlanned: [Entry]

        struct Horizon: Codable, Sendable, Identifiable {
            var key: String
            var name: String
            var note: String
            var color: String
            var items: [Entry]
            var id: String { key }
        }

        struct Entry: Codable, Sendable, Identifiable, Hashable {
            var title: String
            var detail: String
            var id: String { title }
        }

        struct Shipped: Codable, Sendable, Identifiable, Hashable {
            var title: String
            var detail: String
            var build: Int?
            var url: URL?
            var id: String { title }
        }
    }

    // MARK: Fetching

    /// Fetched, or the last copy that arrived, or nothing.
    ///
    /// The cache is the point. These screens have to say something useful on a
    /// plane, and "couldn't load" under a heading called What's Coming reads
    /// like the app has no plans rather than no signal.
    enum Result<Value: Sendable>: Sendable {
        case fresh(Value)
        case cached(Value, fetched: Date)
        case failed(String)

        var value: Value? {
            switch self {
            case .fresh(let v): v
            case .cached(let v, _): v
            case .failed: nil
            }
        }
    }

    static func changelog() async -> Result<Changelog> {
        await load(changelogURL, cache: "changelog-feed.json", as: Changelog.self)
    }

    static func roadmap() async -> Result<Roadmap> {
        await load(roadmapURL, cache: "roadmap-feed.json", as: Roadmap.self)
    }

    private static func load<T: Codable & Sendable>(_ url: URL,
                                                    cache name: String,
                                                    as type: T.Type) async -> Result<T> {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            var request = URLRequest(url: url)
            // A stale What's New is worth less than a fast one, but not much
            // less — the protocol cache plus the endpoint's own max-age is the
            // right amount of caching, and this timeout keeps a bad network
            // from holding the screen.
            request.timeoutInterval = 12
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let value = try decoder.decode(T.self, from: data)
            write(data, to: name)
            return .fresh(value)
        } catch {
            log.error("news feed \(url.lastPathComponent) failed: \(error.localizedDescription)")
            if let (data, fetched) = read(name),
               let value = try? decoder.decode(T.self, from: data) {
                return .cached(value, fetched: fetched)
            }
            return .failed(Self.readable(error))
        }
    }

    /// A sentence, not a code.
    ///
    /// This returned `error.localizedDescription`, which for a URLSession
    /// failure is "The operation couldn't be completed. (NSURLErrorDomain
    /// error -1011.)" — printed above an otherwise good fallback line. Fable
    /// saw it on 2026-09-07 with both feeds returning 404. A number nobody can
    /// act on is worse than no second line, and the diagnosis still goes to
    /// the log above, where it belongs.
    static func readable(_ error: Error) -> String {
        guard let url = error as? URLError else {
            return "Something went wrong fetching it."
        }
        switch url.code {
        case .notConnectedToInternet, .networkConnectionLost:
            return "You're offline."
        case .timedOut:
            return "It took too long to answer."
        case .badServerResponse, .cannotFindHost, .fileDoesNotExist, .resourceUnavailable:
            return "The page isn't published yet."
        default:
            return "Couldn't fetch it just now."
        }
    }

    // MARK: Cache

    /// Caches directory, not Application Support: this is a copy of something
    /// public that can always be fetched again, so the system is welcome to
    /// evict it under pressure. It is never backed up and never synced.
    private static func cacheURL(_ name: String) -> URL? {
        try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                                     appropriateFor: nil, create: true)
            .appendingPathComponent(name)
    }

    private static func write(_ data: Data, to name: String) {
        guard let url = cacheURL(name) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func read(_ name: String) -> (Data, Date)? {
        guard let url = cacheURL(name),
              let data = try? Data(contentsOf: url) else { return nil }
        let fetched = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast
        return (data, fetched)
    }
}
