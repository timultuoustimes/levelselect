import SwiftUI
#if canImport(SafariServices) && os(iOS)
import SafariServices

/// In-app Safari view — keeps the user inside LevelSelect, with persistent
/// cookies so the Deku Deals sign-in sticks between visits.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        let vc = SFSafariViewController(url: url, configuration: config)
        vc.preferredControlTintColor = UIColor(LSTheme.accent)
        vc.dismissButtonStyle = .done
        return vc
    }

    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}
#endif

/// Cross-platform "open Deku" helper: sheet browser on iOS, default browser
/// on macOS.
struct DekuLinkTarget: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

extension View {
    /// Presents an in-app browser for the bound target (iOS); opens externally
    /// on macOS. `onDismiss` runs when the browser closes (used to refresh the
    /// wishlist after adding games on Deku).
    @ViewBuilder
    func dekuBrowser(target: Binding<DekuLinkTarget?>, onDismiss: (() -> Void)? = nil) -> some View {
        #if os(iOS)
        sheet(item: target, onDismiss: onDismiss) { link in
            SafariView(url: link.url)
                .ignoresSafeArea()
        }
        #else
        onChange(of: target.wrappedValue?.id) { _, _ in
            if let url = target.wrappedValue?.url {
                NSWorkspace.shared.open(url)
                target.wrappedValue = nil
                onDismiss?()
            }
        }
        #endif
    }
}

enum DekuLinks {
    static let home = URL(string: "https://www.dekudeals.com")!

    static func search(for name: String) -> URL {
        var components = URLComponents(string: "https://www.dekudeals.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: name)]
        return components.url ?? home
    }
}
