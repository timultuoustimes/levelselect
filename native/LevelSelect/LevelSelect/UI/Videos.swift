import SwiftUI
import SwiftData
#if canImport(WebKit)
import WebKit
#endif

// MARK: - Player dock (16:9, IFrame API bridge for synced resume)

/// Top-docked YouTube player. Uses the IFrame Player API so the app can
/// sample the playhead (every 5s + on state changes) and store it on the
/// video record — resume survives app restarts and syncs via CloudKit.
/// Playlists also track which part is playing.
struct VideoPlayerDock: View {
    let video: GameVideo
    var onClose: () -> Void
    @Environment(\.modelContext) private var context

    var body: some View {
        ZStack(alignment: .topTrailing) {
            YouTubePlayerView(video: video) { seconds, part in
                Repository(context).updateVideoProgress(video, seconds: seconds, partIndex: part)
                try? context.save()
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .background(.black)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .padding(7)
                    .background(.black.opacity(0.55), in: .circle)
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .padding(8)
        }
    }
}

#if canImport(WebKit) && !os(watchOS)
struct YouTubePlayerView {
    let video: GameVideo
    var onProgress: @MainActor (Double, Int?) -> Void

    func makeWebView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        #if os(iOS)
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        #endif
        config.preferences.isElementFullscreenEnabled = true
        config.userContentController.add(context.coordinator, name: "progress")
        let webView = WKWebView(frame: .zero, configuration: config)
        #if os(iOS)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        #endif
        webView.loadHTMLString(Self.html(for: video),
                               baseURL: URL(string: "https://www.youtube-nocookie.com"))
        return webView
    }

    func makeCoordinator() -> Coordinator { Coordinator(onProgress: onProgress) }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        let onProgress: @MainActor (Double, Int?) -> Void
        init(onProgress: @escaping @MainActor (Double, Int?) -> Void) { self.onProgress = onProgress }

        func userContentController(_ controller: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "progress",
                  let body = message.body as? [String: Any],
                  let t = (body["t"] as? NSNumber)?.doubleValue else { return }
            let part = (body["i"] as? NSNumber)?.intValue
            let resolvedPart = (part ?? -1) >= 0 ? part : nil
            let handler = onProgress
            Task { @MainActor in
                handler(t, resolvedPart)
            }
        }
    }

    /// Host page for the IFrame API player, seeded with the stored position.
    static func html(for video: GameVideo) -> String {
        let start = max(0, Int(video.watchedSeconds.rounded(.down)) - 2)
        let setup: String
        switch video.kind {
        case .video:
            setup = "videoId:'\(video.youtubeID)',playerVars:{playsinline:1,start:\(start),rel:0}"
        case .playlist:
            setup = "playerVars:{listType:'playlist',list:'\(video.youtubeID)',index:\(video.watchedPartIndex),start:\(start),playsinline:1,rel:0}"
        }
        return """
        <!doctype html><html><head>
        <meta name="viewport" content="initial-scale=1, maximum-scale=1">
        <style>html,body{margin:0;height:100%;background:#000;overflow:hidden}
        #p{position:absolute;inset:0;width:100%;height:100%}</style></head><body>
        <div id="p"></div>
        <script src="https://www.youtube.com/iframe_api"></script>
        <script>
        let player;
        function onYouTubeIframeAPIReady(){
          player = new YT.Player('p', {\(setup),
            events:{ onStateChange: report }});
          setInterval(report, 5000);
        }
        function report(){
          try{
            const t = player.getCurrentTime ? (player.getCurrentTime()||0) : 0;
            let i = -1;
            if (player.getPlaylistIndex) { i = player.getPlaylistIndex(); }
            window.webkit.messageHandlers.progress.postMessage({t:t, i:i});
          }catch(e){}
        }
        </script></body></html>
        """
    }
}

#if os(macOS)
extension YouTubePlayerView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateNSView(_ view: WKWebView, context: Context) {}
}
#else
extension YouTubePlayerView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateUIView(_ view: WKWebView, context: Context) {}
}
#endif
#endif

// MARK: - Grouped video list

/// Play-style grouped list: playlist groups, custom groups, and the default
/// "Videos" group, with an add-URL field. Tap to play; long-press to manage.
struct VideoListView: View {
    let game: Game
    @Binding var playing: GameVideo?
    @Environment(\.modelContext) private var context

    @State private var newURL = ""
    @State private var adding = false
    @State private var addError: String?
    @State private var movingVideo: GameVideo?
    @State private var newGroupName = ""

    private var repo: Repository { Repository(context) }

    private var liveVideos: [GameVideo] {
        (game.videos ?? [])
            .filter { $0.deletedAt == nil }
            .sorted { $0.orderIndex < $1.orderIndex }
    }

    private var groups: [(name: String, videos: [GameVideo])] {
        let grouped = Dictionary(grouping: liveVideos, by: \.groupName)
        return grouped
            .map { (name: $0.key, videos: $0.value) }
            .sorted { ($0.videos.first?.orderIndex ?? 0) < ($1.videos.first?.orderIndex ?? 0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(groups, id: \.name) { group in
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.name.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .kerning(0.6)
                    ForEach(group.videos) { video in
                        row(video)
                    }
                }
            }

            addField
        }
        .alert("Move to group", isPresented: Binding(
            get: { movingVideo != nil },
            set: { if !$0 { movingVideo = nil } }
        )) {
            TextField("Group name", text: $newGroupName)
            Button("Move") {
                if let video = movingVideo {
                    repo.moveVideo(video, toGroup: newGroupName)
                }
                movingVideo = nil
            }
            Button("Cancel", role: .cancel) { movingVideo = nil }
        }
    }

    private func row(_ video: GameVideo) -> some View {
        Button {
            playing = video
        } label: {
            HStack(spacing: 10) {
                thumb(video)
                VStack(alignment: .leading, spacing: 3) {
                    Text(video.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 5) {
                        if video.kind == .playlist {
                            chip("Playlist", tint: .pink)
                        }
                        if let channel = video.channel {
                            chip(channel, tint: .gray)
                        }
                        if let resume = resumeLabel(video) {
                            chip(resume, tint: .green)
                        }
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: playing?.id == video.id ? "waveform" : "play.circle")
                    .foregroundStyle(LSTheme.accent)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                newGroupName = video.groupName
                movingVideo = video
            } label: {
                Label("Move to Group…", systemImage: "folder")
            }
            if let url = URL(string: video.urlString) {
                Link(destination: url) {
                    Label("Open in YouTube", systemImage: "arrow.up.right.square")
                }
            }
            Button(role: .destructive) {
                if playing?.id == video.id { playing = nil }
                repo.deleteVideo(video)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func thumb(_ video: GameVideo) -> some View {
        Group {
            if let s = video.thumbnailURL, let url = URL(string: s) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        Rectangle().fill(.quaternary)
                    }
                }
            } else {
                ZStack {
                    Rectangle().fill(.quaternary)
                    Image(systemName: "play.rectangle").foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 74, height: 42)
        .clipShape(.rect(cornerRadius: 7))
    }

    private func chip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(tint.opacity(0.18), in: .capsule)
            .foregroundStyle(tint == .gray ? AnyShapeStyle(.secondary) : AnyShapeStyle(tint))
            .lineLimit(1)
    }

    private func resumeLabel(_ video: GameVideo) -> String? {
        guard video.watchedSeconds > 3 || video.watchedPartIndex > 0 else { return nil }
        let time = Format.timestamp(video.watchedSeconds)
        return video.kind == .playlist
            ? "Part \(video.watchedPartIndex + 1) · \(time)"
            : "▶ \(time)"
    }

    private var addField: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField("Paste a YouTube video or playlist URL…", text: $newURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    #if !os(macOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
                    .onSubmit(add)
                if adding {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Add", action: add)
                        .buttonStyle(.borderless)
                        .disabled(newURL.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            if let error = addError {
                Text(error).font(.caption2).foregroundStyle(.orange)
            }
        }
    }

    private func add() {
        let urlString = newURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlString.isEmpty else { return }
        guard let parsed = YouTubeService.parse(urlString) else {
            addError = "That doesn't look like a YouTube video or playlist link."
            return
        }
        addError = nil
        adding = true
        Task {
            let metadata = await YouTubeService.metadata(for: urlString)
            repo.addVideo(to: game, parsed: parsed, urlString: urlString, metadata: metadata)
            newURL = ""
            adding = false
        }
    }
}
