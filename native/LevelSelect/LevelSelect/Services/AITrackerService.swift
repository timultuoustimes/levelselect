import Foundation

/// Native client for the deployed `ai-tracker-generator` Supabase edge
/// function (same backend the web app uses — Claude generates a full tracker
/// schema server-side; no AI credentials in the app). Takes 1–2 minutes, sometimes longer for big games.
enum AITrackerService {
    struct GenerationError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private static let functionURL = URL(
        string: "https://sextftevxqrtodlmnyve.supabase.co/functions/v1/ai-tracker-generator")!

    /// Generate a tracker schema. `referenceText` switches to paste mode
    /// (faster, grounded in a guide the user supplies); nil = auto mode
    /// (server web-searches for the best guide). `igdbID`, when known, rides
    /// along unused today — the edge function ignores it — but gives a
    /// future shared tracker cache a stable key from day one, since
    /// `gameName` alone collides across remasters, regional titles, and
    /// Deluxe/Definitive editions.
    static func generate(gameName: String, igdbID: Int? = nil, referenceText: String? = nil) async throws -> Data {
        var body: [String: Any] = ["gameName": gameName]
        if let igdbID { body["igdbID"] = igdbID }
        if let referenceText, !referenceText.isEmpty {
            body["mode"] = "paste"
            body["payload"] = referenceText
        } else {
            body["mode"] = "auto"
        }
        // Edge functions cap at 150s wall clock; wait just under that.
        let root = try await post(body, timeout: 145)
        return try schema(from: root)
    }

    /// One category proposal from the planning stage.
    struct PlannedCategory: Sendable, Hashable {
        let name: String
        let plannedCount: Int?
        /// Too large to be worth listing row by row; it will fill as a single
        /// running total. The fill re-decides this by the same rule, so the
        /// flag is not what makes it happen — it is what lets the placeholder
        /// say what is coming, instead of promising 900 rows and yielding one.
        let counted: Bool
    }

    /// Ask what a tracker for this game should be *divided into* — headings and
    /// rough sizes, no items.
    ///
    /// Fast and cheap precisely because it generates nothing: the answer is a
    /// paragraph, not nine hundred collectibles. It exists for the person who
    /// doesn't know what to plan, and it is a better first step even for
    /// someone who does, since the shape can be corrected before anyone spends
    /// two minutes filling it in.
    static func plan(gameName: String, igdbID: Int? = nil) async throws -> [PlannedCategory] {
        var body: [String: Any] = ["gameName": gameName, "mode": "plan"]
        if let igdbID { body["igdbID"] = igdbID }
        let root = try await post(body, timeout: 75)

        guard let plan = root["plan"] as? [String: Any],
              let raw = plan["categories"] as? [[String: Any]], !raw.isEmpty else {
            throw GenerationError(message: "The planner didn't suggest any categories. Try again.")
        }
        return raw.compactMap { entry in
            guard let name = (entry["name"] as? String)?
                .trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
            let count = entry["plannedCount"] as? Int
            return PlannedCategory(name: name, plannedCount: (count ?? 0) > 0 ? count : nil,
                                   counted: (entry["counted"] as? Bool) ?? false)
        }
    }

    /// Generate the items for ONE named category.
    ///
    /// The whole-tracker generator was the only unit available, so filling a
    /// single planned category meant generating the entire game and discarding
    /// everything else — which on Breath of the Wild timed out before it could
    /// return an eighteen-item category.
    static func generateCategory(gameName: String, categoryName: String,
                                 expectedCount: Int? = nil, igdbID: Int? = nil) async throws -> Data {
        var body: [String: Any] = [
            "gameName": gameName, "mode": "category", "categoryName": categoryName,
        ]
        if let expectedCount, expectedCount > 0 { body["expectedCount"] = expectedCount }
        if let igdbID { body["igdbID"] = igdbID }
        // Same ceiling as a full generation: the edge function caps at 150s,
        // and a long category can legitimately use most of it.
        let root = try await post(body, timeout: 145)
        return try schema(from: root)
    }

    // MARK: Transport

    private static func post(_ body: [String: Any], timeout: TimeInterval) async throws -> [String: Any] {
        var request = URLRequest(url: functionURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        EdgeFunctions.authorize(&request)
        request.timeoutInterval = timeout
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .timedOut {
            throw GenerationError(message: "Generation timed out — the AI took too long. Try again, or use a simpler game name.")
        } catch {
            throw GenerationError(message: "Network error — check your connection and try again.")
        }

        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let message = (root?["error"] as? String) ?? "Generator failed (\(status))."
            throw GenerationError(message: message)
        }
        guard let root else {
            throw GenerationError(message: "The generator returned something unreadable. Try again.")
        }
        return root
    }

    private static func schema(from root: [String: Any]) throws -> Data {
        guard let structuredData = root["structuredData"] as? [String: Any],
              let categories = structuredData["categories"] as? [[String: Any]],
              !categories.isEmpty else {
            throw GenerationError(message: "The generator returned no tracker content. Try again.")
        }
        return try JSONSerialization.data(withJSONObject: structuredData)
    }
}
