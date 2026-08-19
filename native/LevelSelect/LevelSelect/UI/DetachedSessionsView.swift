import SwiftUI
import SwiftData

/// Give detached play sessions back to a game.
///
/// These records hold real recorded time that lost its link to a playthrough,
/// so they sit outside every total, every history and the export. The app
/// still can't infer where they belong — nothing in the store says — but the
/// person who played them usually knows exactly, and leaving the time lost
/// for a reason that is really just the app's ignorance is the wrong answer.
/// Surfacing them was step one; this is the part that gets them back.
struct DetachedSessionsView: View {
    @Environment(\.modelContext) private var context

    // Sorted below rather than in the query: the compound predicate plus a
    // sort descriptor pushes the type-checker past its limit here.
    @Query(filter: #Predicate<Session> {
        $0.playthrough == nil && $0.deletedAt == nil
    }) private var detachedUnsorted: [Session]

    private var detached: [Session] {
        detachedUnsorted.sorted { $0.startDate > $1.startDate }
    }

    @Query(filter: #Predicate<Game> { $0.deletedAt == nil }, sort: \Game.name)
    private var games: [Game]

    @State private var assigning: Session?
    @State private var gameSearch = ""
    @State private var confirmingDelete: Session?

    private var repo: Repository { Repository(context) }

    var body: some View {
        List {
                if detached.isEmpty {
                    ContentUnavailableView("Nothing detached",
                                           systemImage: "checkmark.circle",
                                           description: Text("Every recorded session belongs to a game."))
                } else {
                    Section {
                        ForEach(detached) { session in
                            Button {
                                assigning = session
                            } label: {
                                row(session)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    confirmingDelete = session
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                        }
                    } footer: {
                        Text("Tap a session to put it back under a game — its time then counts toward that game's total again. Swipe to remove one that isn't worth keeping.")
                    }
                }
            }
        .navigationTitle("Detached sessions")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        // Pushed, not presented: this view lives inside the Settings sheet,
        // and a sheet inside a sheet was being torn down the instant a
        // root-level prompt tried to present. The game picker below is the
        // only modal here, and it is the innermost one.
        .sheet(item: $assigning) { session in
            gamePicker(for: session)
        }
        .confirmationDialog("Remove this session?",
                            isPresented: Binding(get: { confirmingDelete != nil },
                                                 set: { if !$0 { confirmingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let session = confirmingDelete { repo.deleteSession(session) }
                confirmingDelete = nil
            }
            Button("Cancel", role: .cancel) { confirmingDelete = nil }
        } message: {
            Text("Its recorded time is dropped from the library. The record is tombstoned rather than erased, so it can still be recovered from a backup or export.")
        }
    }

    private func row(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(session.startDate, format: .dateTime.month().day().year().hour().minute())
                    .font(.subheadline.weight(.medium))
                if session.state != .stopped {
                    Text("STILL RUNNING")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(.orange.opacity(0.25), in: .capsule)
                }
            }
            HStack(spacing: 4) {
                if let device = session.originDevice {
                    Text(device)
                    Text("·")
                }
                Text(Format.duration(session.elapsed()))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .contentShape(.rect)
    }

    private func gameRow(_ game: Game) -> some View {
        let total: TimeInterval = game.livePlaythroughs.reduce(0) { $0 + $1.totalPlaytime() }
        return HStack {
            Text(game.name)
            Spacer()
            Text(Format.duration(total))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(.rect)
    }

    private var searchedGames: [Game] {
        let query = gameSearch.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return games }
        return games.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private func gamePicker(for session: Session) -> some View {
        NavigationStack {
            List(searchedGames) { game in
                Button {
                    repo.reattachSession(session, to: game)
                    assigning = nil
                    gameSearch = ""
                } label: {
                    gameRow(game)
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Which game?")
            .searchable(text: $gameSearch, prompt: "Search games")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { assigning = nil; gameSearch = "" }
                }
            }
        }
    }
}
