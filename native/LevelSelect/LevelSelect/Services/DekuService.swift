import Foundation
import Observation

/// One entry in a public Deku Deals wishlist (via the sanctioned `.json`
/// suffix on a shared wishlist URL — an intentional feature, not scraping).
struct DekuWishlistItem: Identifiable, Hashable, Sendable, Codable {
    let name: String
    let link: String
    let addedAt: Date?
    let desiredFormat: String?

    var id: String { link }
    var url: URL? { URL(string: link) }
}

/// Fetches + caches the user's public Deku wishlist. The wishlist page URL is
/// user-provided in Settings (never hardcoded — the repo is public).
@MainActor
@Observable
final class DekuWishlistStore {
    static let urlDefaultsKey = "dekuWishlistURL"
    private static let cacheKey = "dekuWishlistCache"

    var items: [DekuWishlistItem] = []
    var lastUpdated: Date?
    var isLoading = false
    var errorMessage: String?

    /// STORED so @Observable tracks it (a computed UserDefaults passthrough is
    /// invisible to Observation — the setup screen never re-rendered on
    /// Connect). Persisted via didSet.
    var configuredURL: String {
        didSet { UserDefaults.standard.set(configuredURL, forKey: Self.urlDefaultsKey) }
    }

    var isConfigured: Bool {
        !configuredURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init() {
        configuredURL = UserDefaults.standard.string(forKey: Self.urlDefaultsKey) ?? ""
        loadCache()
    }

    /// Normalize whatever the user pasted into the `.json` endpoint.
    private var jsonURL: URL? {
        var raw = configuredURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if !raw.lowercased().hasPrefix("http") { raw = "https://" + raw }
        while raw.hasSuffix("/") { raw.removeLast() }
        if !raw.hasSuffix(".json") { raw += ".json" }
        return URL(string: raw)
    }

    func refresh() async {
        guard let url = jsonURL else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                errorMessage = "Couldn't load wishlist — is it set to public?"
                return
            }
            let parsed = try Self.parse(data)
            items = parsed
            lastUpdated = .now
            saveCache(data)
        } catch {
            errorMessage = "Couldn't reach Deku Deals."
        }
    }

    // MARK: Parsing (lenient — fields beyond name/link are optional)

    private static func parse(_ data: Data) throws -> [DekuWishlistItem] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawItems = root["items"] as? [[String: Any]] else { return [] }
        let iso = ISO8601DateFormatter()
        return rawItems.compactMap { raw in
            guard let name = raw["name"] as? String,
                  let link = raw["link"] as? String else { return nil }
            return DekuWishlistItem(
                name: name,
                link: link,
                addedAt: (raw["added_at"] as? String).flatMap { iso.date(from: $0) },
                desiredFormat: raw["desired_format"] as? String
            )
        }
        .sorted { ($0.addedAt ?? .distantPast) > ($1.addedAt ?? .distantPast) }
    }

    // MARK: Offline cache

    private func loadCache() {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey),
              let parsed = try? Self.parse(data) else { return }
        items = parsed
    }

    private func saveCache(_ data: Data) {
        UserDefaults.standard.set(data, forKey: Self.cacheKey)
    }
}
