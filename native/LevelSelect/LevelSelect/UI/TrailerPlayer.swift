import SwiftUI
#if canImport(WebKit) && !os(watchOS)
import WebKit

/// A trailer, playing where you are.
///
/// The first attempt pointed the in-app browser at a YouTube embed URL and got
/// **Error 153** — YouTube refuses a bare `/embed/` load whose referrer it does
/// not recognize. The app already had the answer: `YouTubePlayerView` loads the
/// IFrame API from HTML with a `youtube-nocookie.com` base URL, which is what
/// makes the referrer valid, and it has played guides and videos for builds.
///
/// This is that, minus everything the game page needs and a trailer does not —
/// no resume position, no playlist parts, no progress reporting back to a
/// model. Tim: "we also have video precedent in the app for guides & videos
/// that doesn't pull up YouTube awkwardly in a browser."
struct TrailerPlayer {
    let youtubeID: String

    fileprivate func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        #if os(iOS)
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        #endif
        config.preferences.isElementFullscreenEnabled = true
        let webView = WKWebView(frame: .zero, configuration: config)
        #if os(iOS)
        webView.isOpaque = false
        webView.scrollView.isScrollEnabled = false
        #endif
        // The base URL is the load-bearing part: without it YouTube sees no
        // origin it trusts and refuses to configure the player at all.
        webView.loadHTMLString(Self.html(for: youtubeID),
                               baseURL: URL(string: "https://www.youtube-nocookie.com"))
        return webView
    }

    fileprivate static func html(for id: String) -> String {
        """
        <!doctype html><html><head>
        <meta name="viewport" content="initial-scale=1, maximum-scale=1">
        <style>html,body{margin:0;height:100%;background:#000;overflow:hidden}
        #p{position:absolute;inset:0;width:100%;height:100%}</style></head><body>
        <div id="p"></div>
        <script src="https://www.youtube.com/iframe_api"></script>
        <script>
        let player;
        function onYouTubeIframeAPIReady(){
          player = new YT.Player('p', {
            videoId:'\(id)',
            playerVars:{playsinline:1,rel:0,autoplay:1},
            events:{onReady:e=>e.target.playVideo()}
          });
        }
        </script></body></html>
        """
    }
}

extension TrailerPlayer {
    /// **Point the live player at a different trailer.**
    ///
    /// The update pass was empty, and SwiftUI keeps ONE representable and one
    /// web view for a given position in the tree — so tapping a second
    /// trailer while the first was playing changed `youtubeID` and nothing
    /// else. The only way to watch the other one was to close the player
    /// first. Tim, 2026-09-10: *"I can't tap the other trailer to open it
    /// without first tapping the X on the open video to close it out. I
    /// should be able to just tap the next video and have it replace the
    /// video that's already open."*
    ///
    /// Exactly the bug `YouTubePlayerView.refresh` carries a note about, in
    /// the other player — the saved-videos dock hit it first and this one was
    /// written afterwards without the fix.
    ///
    /// Guarded on the id, because the update pass runs for any reason at all
    /// and reloading unconditionally would restart the trailer every time the
    /// page around it re-rendered.
    fileprivate func refresh(_ webView: WKWebView, _ coordinator: Coordinator) {
        guard coordinator.loadedID != youtubeID else { return }
        coordinator.loadedID = youtubeID
        webView.loadHTMLString(Self.html(for: youtubeID),
                               baseURL: URL(string: "https://www.youtube-nocookie.com"))
    }

    /// Holds the id the web view is actually showing. `makeCoordinator` runs
    /// once per player, which is what makes it the right place to remember.
    final class Coordinator {
        var loadedID: String?
    }
}

#if os(iOS)
extension TrailerPlayer: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> WKWebView {
        context.coordinator.loadedID = youtubeID
        return makeWebView()
    }
    func updateUIView(_ webView: WKWebView, context: Context) {
        refresh(webView, context.coordinator)
    }
}
#else
extension TrailerPlayer: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> WKWebView {
        context.coordinator.loadedID = youtubeID
        return makeWebView()
    }
    func updateNSView(_ webView: WKWebView, context: Context) {
        refresh(webView, context.coordinator)
    }
}
#endif
#endif
