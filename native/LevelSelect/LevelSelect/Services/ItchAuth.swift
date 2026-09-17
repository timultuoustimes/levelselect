import Foundation
#if canImport(AuthenticationServices) && !os(watchOS)
import AuthenticationServices

/// The browser half of the OAuth flow.
///
/// `ASWebAuthenticationSession` rather than an in-app web view on purpose: it
/// runs in Safari's own process, so the app never sees the itch.io login page
/// and could not read what is typed into it even if it wanted to. For a screen
/// where someone enters a password that is the difference between asking for
/// permission and asking for a password.
enum ItchAuth {
    @MainActor
    static func run(url: URL, scheme: String) async throws -> URL {
        // No window to present over (the app is mid-launch or backgrounded):
        // the sheet can't appear, so don't start one.
        guard ContextProvider.shared.hasAnchor else { throw CancellationError() }
        return try await withCheckedThrowingContinuation { continuation in
            // @Sendable so the closure doesn't inherit run's main-actor
            // isolation: the system calls it on a background queue, and the
            // runtime's isolation check crashes the app there. It only resumes
            // the continuation, which is safe from any thread.
            let session = ASWebAuthenticationSession(
                url: url, callbackURLScheme: scheme
            ) { @Sendable callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                } else if let error = error as? ASWebAuthenticationSessionError,
                          error.code == .canceledLogin {
                    continuation.resume(throwing: CancellationError())
                } else {
                    continuation.resume(throwing: error ?? CancellationError())
                }
            }
            session.presentationContextProvider = ContextProvider.shared
            // A fresh session every time. Without this the browser reuses an
            // existing itch.io or Microsoft login, which is convenient right
            // up until someone is trying to connect a different account and
            // cannot see why they keep getting the first one. (This read
            // `false` under this same comment from the day it was written.)
            session.prefersEphemeralWebBrowserSession = true
            session.start()
        }
    }

    /// Where to put the sheet. `ASWebAuthenticationSession` will not present
    /// without one.
    private final class ContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
        static let shared = ContextProvider()
        #if os(macOS)
        var hasAnchor: Bool { true }

        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
        }
        #else
        private var scenes: [UIWindowScene] {
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        }

        var hasAnchor: Bool { !scenes.isEmpty }

        /// The key window, else a window on the first scene — never a bare
        /// `ASPresentationAnchor()`, which iOS 26 deprecates. `run` checks
        /// `hasAnchor` first, so a scene is there.
        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            let scenes = scenes
            if let key = scenes.flatMap(\.windows).first(where: \.isKeyWindow) { return key }
            if let window = scenes.first?.windows.first { return window }
            return ASPresentationAnchor(windowScene: scenes[0])
        }
        #endif
    }
}
#endif
