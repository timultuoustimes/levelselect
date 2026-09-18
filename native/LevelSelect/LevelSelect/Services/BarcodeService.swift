import Foundation

/// A game box's barcode → the game, through ScanDex.
///
/// ScanDex (scandex.gamery.app, by the Gamery team) answers a barcode with an
/// IGDB id — LevelSelect's own key — so a match goes straight into the normal
/// add flow. See the vault note "LevelSelect ScanDex barcode API". Reached
/// through `scandex-proxy`, which holds the access token; until that's set,
/// lookups say `.unavailable` and scanning still remembers barcodes on the
/// games you add, so a second scan of the same box always works.
///
/// **What's sent:** the barcode number. And when ScanDex didn't know a barcode
/// and you then picked its game by hand, that pairing, to help the database —
/// the add screen says so before you add.
enum BarcodeService {
    enum Lookup: Equatable, Sendable {
        case matched(igdbID: Int, name: String?, platform: String?, platformID: Int?)
        /// ScanDex has the barcode but no game for it yet.
        case unmatched
        /// ScanDex has never seen it.
        case unknown
        /// No network, or the proxy isn't set up.
        case unavailable(String)
    }

    /// Digits only, and the UPC-A/EAN-13 twins folded: `0711719546658` and
    /// `711719546658` are the same box (ScanDex says so too).
    static func normalized(_ raw: String) -> String? {
        let digits = raw.filter(\.isNumber)
        guard (8...14).contains(digits.count) else { return nil }
        // All zeros is no box: ScanDex "matches" it to Uncharted 3 (09-18).
        guard digits.contains(where: { $0 != "0" }) else { return nil }
        if digits.count == 13, digits.hasPrefix("0") { return String(digits.dropFirst()) }
        return digits
    }

    /// Whether a stored barcode is this one.
    static func same(_ a: String, _ b: String) -> Bool {
        normalized(a) == normalized(b) && normalized(a) != nil
    }

    private static let functionURL = URL(
        string: "https://sextftevxqrtodlmnyve.supabase.co/functions/v1/scandex-proxy")!

    static func lookup(_ barcode: String) async -> Lookup {
        guard let value = normalized(barcode) else { return .unknown }
        guard let json = try? await post(["mode": "lookup", "value": value]) else {
            return .unavailable("Couldn't reach the barcode lookup.")
        }
        if let error = json["error"] as? String { return .unavailable(error) }
        switch json["status"] as? String {
        case "matched":
            guard let id = (json["igdbID"] as? NSNumber)?.intValue else { return .unmatched }
            return .matched(igdbID: id, name: json["name"] as? String,
                            platform: json["platform"] as? String,
                            platformID: (json["platformID"] as? NSNumber)?.intValue)
        case "unmatched": return .unmatched
        case "unknown": return .unknown
        // Anything else — the function not deployed yet answers with
        // Supabase's own NOT_FOUND — is "can't look it up", not "no such game".
        default: return .unavailable("Barcode lookups aren't set up yet.")
        }
    }

    /// Tell ScanDex which game an unknown barcode was. Best effort, silent.
    static func suggest(barcode: String, igdbID: Int, name: String, platform: String) async {
        guard let value = normalized(barcode), let platformID = igdbPlatformIDs[platform] else { return }
        _ = try? await post(["mode": "suggest", "value": value, "igdbID": igdbID,
                             "platformID": platformID, "platform": platform, "name": name])
    }

    /// IGDB's ids for the platforms people scan boxes for. ScanDex's create
    /// endpoint wants the id, and IGDB results carry only the name.
    static let igdbPlatformIDs: [String: Int] = [
        "Nintendo Switch 2": 508, "Nintendo Switch": 130, "Wii U": 41, "Wii": 5,
        "Nintendo 3DS": 37, "Nintendo DS": 20, "Nintendo GameCube": 21, "Game Boy Advance": 24,
        "PlayStation 5": 167, "PlayStation 4": 48, "PlayStation 3": 9, "PlayStation 2": 8,
        "PlayStation": 7, "PlayStation Vita": 46, "PlayStation Portable": 38,
        "Xbox Series X|S": 169, "Xbox One": 49, "Xbox 360": 12, "Xbox": 11,
        "PC (Microsoft Windows)": 6,
    ]

    private static func post(_ body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: functionURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        EdgeFunctions.authorize(&request)
        request.timeoutInterval = 15
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}
