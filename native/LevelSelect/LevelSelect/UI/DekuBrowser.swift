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
        // (No preferredControlTintColor — deprecated in iOS 26; tinting now
        // interferes with the system's Liquid Glass background effects.)
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

#if canImport(WebKit)
import WebKit

/// Embedded Deku Deals browser pane (iPad/macOS split view): persistent
/// cookie store so the Deku sign-in sticks, in-place navigation, and a
/// minimal chrome (back / reload / sync wishlist / open externally).
struct DekuBrowserPane: View {
    @Binding var url: URL
    /// Called when the user taps the sync button (refresh the wishlist after
    /// adding games in the pane).
    var onSyncRequest: () -> Void

    @State private var webView: WKWebView?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button {
                    webView?.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(webView?.canGoBack != true)
                Button {
                    webView?.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                Spacer()
                Text(webView?.url?.host() ?? url.host() ?? "dekudeals.com")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button {
                    onSyncRequest()
                } label: {
                    Label("Sync wishlist", systemImage: "arrow.triangle.2.circlepath")
                        .labelStyle(.iconOnly)
                }
                .help("Re-sync the wishlist list")
                if let current = webView?.url ?? Optional(url) {
                    Link(destination: current) {
                        Image(systemName: "safari")
                    }
                }
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            DekuWebView(url: url, webView: $webView)
        }
        .background(.ultraThinMaterial)
    }
}

// MainActor: everything here drives WKWebView, and the Representable entry
// points (makeUIView/updateUIView) are main-actor anyway.
@MainActor
private struct DekuWebView {
    let url: URL
    @Binding var webView: WKWebView?

    final class Coordinator {
        /// Last URL the APP commanded — user browsing inside the pane never
        /// changes this, so updates only fire on new row taps.
        var lastCommanded: URL?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeWebView(coordinator: Coordinator) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()   // persistent — sign-in sticks
        #if os(iOS)
        // The add screen opens trailers through this pane. Without these a
        // YouTube embed refuses to start until it is taken fullscreen, which
        // reads as a dead player rather than a video.
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        #endif
        let view = WKWebView(frame: .zero, configuration: config)
        view.load(URLRequest(url: url))
        coordinator.lastCommanded = url
        DispatchQueue.main.async { webView = view }
        return view
    }

    func update(_ view: WKWebView, coordinator: Coordinator) {
        if coordinator.lastCommanded != url {
            coordinator.lastCommanded = url
            view.load(URLRequest(url: url))
        }
    }
}

#if os(macOS)
extension DekuWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { makeWebView(coordinator: context.coordinator) }
    func updateNSView(_ view: WKWebView, context: Context) { update(view, coordinator: context.coordinator) }
}
#else
extension DekuWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { makeWebView(coordinator: context.coordinator) }
    func updateUIView(_ view: WKWebView, context: Context) { update(view, coordinator: context.coordinator) }
}
#endif
#endif

enum DekuLinks {
    static let home = URL(string: "https://www.dekudeals.com")!

    static func search(for name: String) -> URL {
        var components = URLComponents(string: "https://www.dekudeals.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: name)]
        return components.url ?? home
    }
}
