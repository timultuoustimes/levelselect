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
                            Text("\(Format.duration(pt.totalPlaytime())) · \(Int(pt.progressPercent))%")
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
    @State private var tab: Tab = .tracker
    @State private var playing: GameVideo?

    enum Tab: String, CaseIterable {
        case tracker = "Tracker"
        case videos = "Videos"
    }

    private var runTemplate: RunTemplateDTO? {
        game.trackerSchema.flatMap { TrackerSchemaJSON.runTemplate(from: $0.jsonData) }
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
        .navigationTitle(game.activePlaythrough?.name ?? game.name)
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
            CollapsibleSection("Runs", icon: "flag.checkered") {
                RunSectionView(game: game, template: template)
            }
            Divider()
        }
        TrackerSectionView(game: game)
        Divider()
        CollapsibleSection("Videos", icon: "play.rectangle", defaultExpanded: false) {
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
