import Foundation

/// Keeps a request that carries someone's credential on the host it was sent to.
///
/// RetroAchievements and Steam take the key in the query string, and itch.io
/// takes a bearer token. `URLSession` follows a redirect by default to whatever
/// host the response names — Codex, 09-15: nothing stopped a key-bearing request
/// being carried somewhere else. A redirect that stays on the same host over
/// https is followed; anything else is refused, and the caller gets the redirect
/// response itself, which each service reports as a failure.
final class CredentialRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = CredentialRedirectGuard()

    static func allows(from original: URL?, to redirect: URL?) -> Bool {
        guard let from = original?.host?.lowercased(),
              let to = redirect?.host?.lowercased(),
              redirect?.scheme?.lowercased() == "https" else { return false }
        return from == to
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        Self.allows(from: task.originalRequest?.url, to: request.url) ? request : nil
    }

    /// Ephemeral, with no URL cache — a cached response is keyed by the full
    /// URL, key included — and redirects held to the original host.
    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: configuration, delegate: shared, delegateQueue: nil)
    }
}
