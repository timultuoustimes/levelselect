import SwiftUI
#if canImport(WebKit) && !os(watchOS)
import WebKit

/// A trailer, playing where you are.
///
/// The first attempt pointed the in-app browser at a YouTube embed URL and got
/// **Error 153** — YouTube refuses a bare `/embed/` load whose referrer it does
/// not recognise. The app already had the answer: `YouTubePlayerView` loads the
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

#if os(iOS)
extension TrailerPlayer: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { makeWebView() }
    func updateUIView(_ webView: WKWebView, context: Context) {}
}
#else
extension TrailerPlayer: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { makeWebView() }
    func updateNSView(_ webView: WKWebView, context: Context) {}
}
#endif

/// A trailer in a sheet, sized like the video it holds.
struct TrailerSheet: View {
    let youtubeID: String
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack {
                Spacer(minLength: 0)
                TrailerPlayer(youtubeID: youtubeID)
                    .aspectRatio(16 / 9, contentMode: .fit)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
            .navigationTitle(title)
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// `.sheet(item:)` needs identity, and a YouTube id is one.
struct TrailerTarget: Identifiable {
    let youtubeID: String
    let title: String
    var id: String { youtubeID }
}
#endif
