import SwiftUI
import SwiftData

/// Navigation payload for pushing a game's dedicated tracker page.
struct TrackerRoute: Hashable {
    let game: Game
}

/// Compact-mode card on the game page: playthroughs with time + progress and
/// an Open → into the dedicated tracker page (web-app pattern). Opening a
/// playthrough also makes it ACTIVE (sessions/Live Activity follow).
struct CompactTrackerCard: View {
    let game: Game
    /// When set (wide-screen stage), Open uses this instead of pushing.
    var onOpen: ((Playthrough) -> Void)? = nil
    @Environment(\.modelContext) private var context

    private var repo: Repository { Repository(context) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // A game whose timer has never run has no playthrough, so the list
            // below renders nothing — which used to leave compact mode with an
            // empty Tracker section and no way in at all. The destination page
            // creates the playthrough on arrival; this row is the way to reach
            // it. (Fixing only the destination missed that you couldn't get
            // there.)
            if game.livePlaythroughs.isEmpty {
                setUpRow
            }

            ForEach(game.livePlaythroughs) { pt in
                if let onOpen {
                    Button {
                        repo.setActivePlaythrough(pt, for: game)
                        onOpen(pt)
                    } label: {
                        rowContent(pt)
                    }
                    .buttonStyle(.plain)
                } else {
                    NavigationLink(value: TrackerRoute(game: game)) {
                        rowContent(pt)
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded {
                        repo.setActivePlaythrough(pt, for: game)
                    })
                }
            }
        }
    }

    /// Entry point for a game with no playthrough yet. Same destination as a
    /// real row, worded as setup rather than as an existing thing to reopen.
    @ViewBuilder
    private var setUpRow: some View {
        let label = HStack(spacing: 10) {
            Image(systemName: "checklist")
                .font(.caption)
                .foregroundStyle(LSTheme.accent)
                .frame(width: 28, height: 28)
                .background(LSTheme.accent.opacity(0.15), in: .rect(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 2) {
                Text("Set up a tracker").font(.subheadline.weight(.semibold))
                Text("Generate one with AI or add your own goals")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .contentShape(.rect)

        if let onOpen {
            Button {
                let pt = repo.ensureDefaultPlaythrough(for: game)
                onOpen(pt)
            } label: { label }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: TrackerRoute(game: game)) { label }
                .buttonStyle(.plain)
        }
    }

    /// Time, progress, and points where the source scores its items.
    ///
    /// RetroAchievements does; a generated tracker doesn't. Absent rather than
    /// zero for everything else — "0 pts" on a tracker with no notion of
    /// points is noise pretending to be information.
    private func subtitle(_ pt: Playthrough) -> String {
        var parts = ["\(Format.duration(pt.totalPlaytime())) · \(Int(pt.progressPercent))%"]
        let items = game.trackerSchema
            .map { TrackerSchemaJSON.categories(from: $0.jsonData) }?
            .flatMap(\.items) ?? []
        let total = items.compactMap(\.points).reduce(0, +)
        if total > 0 {
            let done = Set((pt.trackerStates ?? [])
                .filter { $0.deletedAt == nil && $0.completed }
                .map(\.itemID))
            let earned = items.filter { done.contains($0.id) }.compactMap(\.points).reduce(0, +)
            parts.append("\(earned)/\(total) pts")
        }
        return parts.joined(separator: " · ")
    }

    private func rowContent(_ pt: Playthrough) -> some View {
                    HStack(spacing: 10) {
                        Image(systemName: "gamecontroller.fill")
                            .font(.caption)
                            .foregroundStyle(LSTheme.accent)
                            .frame(width: 28, height: 28)
                            .background(LSTheme.accent.opacity(0.15), in: .rect(cornerRadius: 7))
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) {
                                Text(pt.name).font(.subheadline.weight(.semibold))
                                if pt.id == game.activePlaythrough?.id {
                                    Circle().fill(.green).frame(width: 5, height: 5)
                                }
                            }
                            Text(subtitle(pt))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("Open")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(LSTheme.accent)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(.rect)
    }
}

/// Dedicated tracker page (compact mode, compact width): the active
/// playthrough's Runs + objective tracker, with the video dock on top when a
/// video is playing (Tim's top-dock design).
struct TrackerPageView: View {
    @Bindable var game: Game
    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab = .tracker
    @State private var playing: GameVideo?

    enum Tab: String, CaseIterable {
        case tracker = "Tracker"
        case videos = "Videos"
    }

    private var runTemplate: RunTemplateDTO? {
        game.trackerSchema.flatMap { TrackerSchemaJSON.runTemplate(from: $0.jsonData) }
    }

    private var trackerTitle: String {
        guard let pt = game.activePlaythrough?.name, pt != "Playthrough" else {
            return game.name
        }
        return "\(game.name) · \(pt)"
    }

    var body: some View {
        VStack(spacing: 0) {
            if let video = playing {
                VideoPlayerDock(video: video) {
                    playing = nil
                }
            }

            if playing != nil {
                segmented
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if tab == .tracker || playing == nil {
                        // In compact mode the tracker is its own page, so
                        // without this you'd have to navigate back to the game
                        // just to start or stop the timer — exactly when you're
                        // most likely to be playing and checking things off.
                        SessionControlsView(game: game)
                        trackerContent
                    } else {
                        VideoListView(game: game, playing: $playing)
                    }
                }
                .padding()
            }
            .scrollIndicators(.hidden)
        }
        .lsBackground()
        // Rotation watcher, not layout. This single-screen tracker page only
        // exists for compact widths; rotate the iPad to landscape and the
        // game page UNDERNEATH it becomes the stage (main page left, tracker
        // right) — leaving this pushed page as a stale copy sitting on top,
        // where Back lands you next to a second tracker. Pop it on the
        // transition so rotation flows straight into the stage. Only on a
        // transition (never on appear, so deliberately opening this page in
        // landscape still works), and never while a video is playing here —
        // popping would kill the playback.
        .background {
            GeometryReader { geo in
                Color.clear
                    // Watches the SAME rule the detail page uses to become
                    // the stage, so the two can never disagree about whether
                    // this page is redundant.
                    .onChange(of: StageLayout.fits(geo.size)) { _, becameStage in
                        guard becameStage,
                              game.resolvedTrackerDisplay == .compact,
                              playing == nil
                        else { return }
                        // Leaving isn't enough: the page behind opens at its
                        // first stage, which shows the game and no tracker —
                        // so rotating with the tracker open used to close it.
                        // Ask the page to open the pane we were just reading.
                        AppNavigator.shared.trackerStageRequest = game.id
                        dismiss()
                    }
            }
        }
        // A game whose timer has never run has no playthrough yet, and the
        // tracker hangs off one — without this you couldn't create or generate
        // a tracker in compact mode until you'd started a session first.
        // Reconcile first: this page can be reached without passing through
        // GameDetailView (Home's tracker route), and it reads exactly the
        // rows a sync race duplicates.
        .task {
            let repo = Repository(context)
            repo.reconcile(game)
            repo.liftTrackerItemDetails(for: game)
            repo.ensureDefaultPlaythrough(for: game)
        }
        // The GAME leads the title — showing only the playthrough name meant
        // an iPhone tracker page titled "Playthrough" with no way to tell
        // which game you were in without swiping back. The playthrough rides
        // along only when it's been deliberately named.
        .navigationTitle(trackerTitle)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    tab = .videos
                    if playing == nil, let first = firstVideo {
                        playing = first
                    }
                } label: {
                    Label("Videos", systemImage: "play.rectangle.fill")
                }
            }
        }
    }

    @ViewBuilder
    private var trackerContent: some View {
        if let template = runTemplate {
            CollapsibleSection("Runs", icon: "arrow.2.squarepath",
                               scope: game.id.uuidString) {
                RunSectionView(game: game, template: template)
            }
            Divider()
        }
        TrackerSectionView(game: game)
        Divider()
        CollapsibleSection("Videos", icon: "play.rectangle", defaultExpanded: false,
                           scope: game.id.uuidString) {
            VideoListView(game: game, playing: $playing)
        }
    }

    private var segmented: some View {
        Picker("View", selection: $tab) {
            ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var firstVideo: GameVideo? {
        (game.videos ?? []).filter { $0.deletedAt == nil }
            .sorted { $0.orderIndex < $1.orderIndex }.first
    }
}
