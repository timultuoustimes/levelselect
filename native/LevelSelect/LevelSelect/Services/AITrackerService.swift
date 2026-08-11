import Foundation

/// Native client for the deployed `ai-tracker-generator` Supabase edge
/// function (same backend the web app uses — Claude generates a full tracker
/// schema server-side; no AI credentials in the app). Takes ~60–90s.
enum AITrackerService {
    struct GenerationError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private static let functionURL = URL(
        string: "https://sextftevxqrtodlmnyve.supabase.co/functions/v1/ai-tracker-generator")!

    /// Generate a tracker schema. `referenceText` switches to paste mode
    /// (faster, grounded in a guide the user supplies); nil = auto mode
    /// (server web-searches for the best guide).
    static func generate(gameName: String, referenceText: String? = nil) async throws -> Data {
        var request = URLRequest(url: functionURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Edge functions cap at 150s wall clock; wait just under that.
        request.timeoutInterval = 145

        var body: [String: Any] = ["gameName": gameName]
        if let referenceText, !referenceText.isEmpty {
            body["mode"] = "paste"
            body["payload"] = referenceText
        } else {
            body["mode"] = "auto"
        }
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
        guard let structuredData = root?["structuredData"] as? [String: Any],
              let categories = structuredData["categories"] as? [[String: Any]],
              !categories.isEmpty else {
            throw GenerationError(message: "The generator returned no tracker content. Try again.")
        }
        return try JSONSerialization.data(withJSONObject: structuredData)
    }
}
