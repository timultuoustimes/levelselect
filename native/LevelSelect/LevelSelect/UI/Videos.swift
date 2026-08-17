import SwiftUI
import SwiftData
#if canImport(WebKit)
import WebKit
#endif

/// JS to jump a live player to a playlist part, landing where you left it.
///
/// The seek is deferred because `playVideoAt` loads the new part
/// asynchronously — seeking immediately would move the part you're leaving.
private func playlistJump(to index: Int, in video: GameVideo) -> String {
    let seconds = video.parts.indices.contains(index) ? video.parts[index].seconds : 0
    let start = max(0, Int(seconds.rounded(.down)) - 2)
    guard start > 0 else { return "player.playVideoAt(\(index))" }
    return "player.playVideoAt(\(index));setTimeout(function(){try{player.seekTo(\(start),true)}catch(e){}},700);"
}

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
            YouTubePlayerView(video: video, onProgress: { seconds, part in
                Repository(context).updateVideoProgress(video, seconds: seconds, partIndex: part)
                PersistenceMonitor.shared.commit(context)
            }, onPlaylist: { ids in
                harvestParts(ids: ids)
            })
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

    /// Fill the parts cache the first time the player reports the playlist.
    private func harvestParts(ids: [String]) {
        guard video.kind == .playlist, video.parts.count != ids.count else { return }
        Task {
            let titles = await YouTubeService.titles(for: ids)
            Repository(context).cachePlaylistParts(video, ids: ids, titles: titles)
            PersistenceMonitor.shared.commit(context)
        }
    }
}

// MARK: - Playlist parts sheet

/// "View parts": lists a playlist's individual videos; pick one to jump the
/// player straight to it. Parts load via a hidden cued player on first open.
struct PlaylistPartsSheet: View {
    let video: GameVideo
    var onSelect: (Int) -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if video.parts.isEmpty {
                    VStack(spacing: 14) {
                        ProgressView()
                        Text("Loading parts…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        // Hidden cued player — exists only to report the
                        // playlist contents; never visibly plays.
                        YouTubePlayerView(video: video, onProgress: { _, _ in }, onPlaylist: { ids in
                            Task {
                                let titles = await YouTubeService.titles(for: ids)
                                Repository(context).cachePlaylistParts(video, ids: ids, titles: titles)
                                PersistenceMonitor.shared.commit(context)
                            }
                        })
                        .frame(width: 1, height: 1)
                        .opacity(0.01)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(Array(video.parts.enumerated()), id: \.offset) { index, part in
                            Button {
                                onSelect(index)
                                dismiss()
                            } label: {
                                HStack(spacing: 10) {
                                    Text("\(index + 1)")
                                        .font(.caption.monospacedDigit().weight(.semibold))
                                        .frame(width: 26, height: 26)
                                        .background(
                                            index == video.watchedPartIndex
                                                ? LSTheme.accent.opacity(0.35)
                                                : Color.white.opacity(0.07),
                                            in: .circle)
                                    Text(part.title)
                                        .font(.subheadline)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    Spacer()
                                    // Each part carries its own position now, so
                                    // the whole playlist shows how far you got
                                    // in every part rather than only the last
                                    // one you touched.
                                    if part.seconds > 1 {
                                        Label(Format.timestamp(part.seconds),
                                              systemImage: index == video.watchedPartIndex
                                                  ? "play.fill" : "clock")
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(index == video.watchedPartIndex
                                                             ? .green : .secondary)
                                    }
                                }
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(video.title)
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#if canImport(WebKit) && !os(watchOS)
extension Notification.Name {
    /// Sends JS to a live player (object: [videoID: UUID, js: String]).
    static let lsPlayerCommand = Notification.Name("lsPlayerCommand")
}

// MainActor: makeWebView drives WKWebView, and the nested Coordinator is
// already MainActor-inferred via WKScriptMessageHandler — this aligns the
// container so the calls between them are same-isolation.
@MainActor
struct YouTubePlayerView {
    let video: GameVideo
    var onProgress: @MainActor (Double, Int?) -> Void
    var onPlaylist: (@MainActor ([String]) -> Void)? = nil

    /// Command a live player for this video (e.g. jump to a playlist part).
    @MainActor
    static func command(videoID: UUID, js: String) {
        NotificationCenter.default.post(
            name: .lsPlayerCommand, object: nil,
            userInfo: ["videoID": videoID.uuidString, "js": js])
    }

    func makeWebView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        #if os(iOS)
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        #endif
        config.preferences.isElementFullscreenEnabled = true
        config.userContentController.add(context.coordinator, name: "progress")
        let webView = WKWebView(frame: .zero, configuration: config)
        context.coordinator.attach(webView: webView, videoID: video.id.uuidString)
        #if os(iOS)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        #endif
        webView.loadHTMLString(Self.html(for: video),
                               baseURL: URL(string: "https://www.youtube-nocookie.com"))
        return webView
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onProgress: onProgress, onPlaylist: onPlaylist)
    }

    /// Point the live player at a different video.
    ///
    /// SwiftUI keeps one representable instance (and one web view) for the
    /// dock and just calls the update pass when `video` changes — so with an
    /// empty update, tapping a second video in the list re-rendered the row
    /// highlight while the first video kept playing. Reloading here is also
    /// what re-seeds the player at the new video's stored resume position,
    /// and re-attaches the coordinator so playlist-part commands address the
    /// video actually on screen rather than the first one ever loaded.
    func refresh(_ webView: WKWebView, context: Context) {
        // Every pass, not just on a switch: these must never lag behind the
        // video the dock is actually showing.
        context.coordinator.onProgress = onProgress
        context.coordinator.onPlaylist = onPlaylist

        guard context.coordinator.videoID != video.id.uuidString else { return }
        context.coordinator.attach(webView: webView, videoID: video.id.uuidString)
        webView.loadHTMLString(Self.html(for: video),
                               baseURL: URL(string: "https://www.youtube-nocookie.com"))
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        // `var`, not `let`. These closures capture the video they were built
        // for, and SwiftUI rebuilds them whenever the dock is pointed at a
        // different one — but makeCoordinator() runs only ONCE. Holding the
        // original meant a reloaded player reported the NEW video's position
        // through the OLD video's closure, writing one video's playhead onto
        // another. The update pass refreshes them.
        var onProgress: @MainActor (Double, Int?) -> Void
        var onPlaylist: (@MainActor ([String]) -> Void)?
        private weak var webView: WKWebView?
        /// Which video the live player is currently showing. Read by the
        /// update pass to notice when the dock has been pointed elsewhere.
        private(set) var videoID = ""
        private var observer: (any NSObjectProtocol)?

        init(onProgress: @escaping @MainActor (Double, Int?) -> Void,
             onPlaylist: (@MainActor ([String]) -> Void)?) {
            self.onProgress = onProgress
            self.onPlaylist = onPlaylist
            super.init()
        }

        func attach(webView: WKWebView, videoID: String) {
            self.webView = webView
            self.videoID = videoID
            // Re-attaching on a video switch would otherwise stack a second
            // observer on the same coordinator, so one command would evaluate
            // its JS once per video ever loaded into this dock.
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = NotificationCenter.default.addObserver(
                forName: .lsPlayerCommand, object: nil, queue: .main
            ) { [weak self] note in
                // The block is nonisolated to the compiler; queue .main means
                // it's really on the main actor. Pull the payload first, then
                // touch isolated state only inside assumeIsolated.
                guard let videoID = note.userInfo?["videoID"] as? String,
                      let js = note.userInfo?["js"] as? String else { return }
                MainActor.assumeIsolated {
                    guard let self, videoID == self.videoID else { return }
                    self.webView?.evaluateJavaScript(js)
                }
            }
        }

        // NOTE: no deinit removal — accessing the token from a nonisolated
        // deinit trips Swift 6 sendability; the block observer dies with us.

        func userContentController(_ controller: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "progress",
                  let body = message.body as? [String: Any] else { return }

            if let ids = body["pl"] as? [String], !ids.isEmpty, let onPlaylist {
                Task { @MainActor in onPlaylist(ids) }
            }
            guard let t = (body["t"] as? NSNumber)?.doubleValue else { return }
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
        // A playlist resumes at the position of the PART it's opening, not at
        // the single scalar shared across every part.
        let resumeAt = video.kind == .playlist ? video.currentPartSeconds : video.watchedSeconds
        let start = max(0, Int(resumeAt.rounded(.down)) - 2)
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
        let player, sentList = false;
        function onYouTubeIframeAPIReady(){
          player = new YT.Player('p', {\(setup),
            events:{ onReady: sendList, onStateChange: function(e){ sendList(); report(); } }});
          setInterval(report, 5000);
        }
        function sendList(){
          try{
            if (sentList || !player.getPlaylist) return;
            const list = player.getPlaylist();
            if (list && list.length){
              sentList = true;
              // Announce the parts only. This used to carry t:0, which the
              // Swift side read as a progress report and wrote over the saved
              // playhead the page had just been seeded with — invisible while
              // playback then overwrote it seconds later, but a real loss if
              // you switched away first. report() supplies positions.
              window.webkit.messageHandlers.progress.postMessage({pl:list});
            }
          }catch(e){}
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
    func updateNSView(_ view: WKWebView, context: Context) { refresh(view, context: context) }
}
#else
extension YouTubePlayerView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateUIView(_ view: WKWebView, context: Context) { refresh(view, context: context) }
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
    @State private var partsVideo: GameVideo?

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
        .sheet(item: $partsVideo) { plVideo in
            PlaylistPartsSheet(video: plVideo) { index in
                Repository(context).setVideoPart(plVideo, index: index)
                PersistenceMonitor.shared.commit(context)
                if playing?.id == plVideo.id {
                    YouTubePlayerView.command(
                        videoID: plVideo.id,
                        js: playlistJump(to: index, in: plVideo))
                } else {
                    playing = plVideo
                }
            }
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
            if video.kind == .playlist {
                Button {
                    partsVideo = video
                } label: {
                    Label("View Parts…", systemImage: "list.number")
                }
            }
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
