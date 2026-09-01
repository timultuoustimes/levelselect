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
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url, callbackURLScheme: scheme
            ) { callback, error in
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
            // existing itch.io login, which is convenient right up until
            // someone is trying to connect a different account and cannot see
            // why they keep getting the first one.
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }

    /// Where to put the sheet. `ASWebAuthenticationSession` will not present
    /// without one.
    private final class ContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
        static let shared = ContextProvider()
        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            #if os(macOS)
            NSApplication.shared.windows.first ?? ASPresentationAnchor()
            #else
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first { $0.isKeyWindow } ?? ASPresentationAnchor()
            #endif
        }
    }
}
#endif
