import SwiftUI
import SwiftData

/// Recently Deleted — the way back.
///
/// Deletion has been soft everywhere since V1, but "recoverable in principle"
/// with no recovery UI is a promise the app was keeping to itself. This
/// screen makes it real: everything deliberately deleted — games,
/// playthroughs, collections — listed with a Restore that is one tap and a
/// Delete Forever that is the app's ONLY hard delete, behind its only
/// double-confirmation.
///
/// No auto-purge, on purpose: nothing here is deleted until the owner says
/// so, and the copy says exactly that. A retention window is a policy
/// decision to make with testers, not a default to guess at.
struct RecentlyDeletedView: View {
    @Environment(\.modelContext) private var context

    /// Local mirror refreshed on every change we make — @Query can't filter
    /// on "deletedAt != nil" alongside the repository's sorting cheaply, and
    /// this screen is transient enough that fetch-on-appear is honest.
    @State private var games: [Game] = []
    @State private var playthroughs: [Playthrough] = []
    @State private var collections: [GameCollection] = []
    @State private var confirmingForever: ForeverTarget?

    private var repo: Repository { Repository(context) }

    enum ForeverTarget: Identifiable {
        case game(Game), playthrough(Playthrough), collection(GameCollection)
        var id: UUID {
            switch self {
            case .game(let g): g.id
            case .playthrough(let p): p.id
            case .collection(let c): c.id
            }
        }
        var name: String {
            switch self {
            case .game(let g): g.name
            case .playthrough(let p): p.name
            case .collection(let c): c.name
            }
        }
    }

    var body: some View {
        List {
            if games.isEmpty && playthroughs.isEmpty && collections.isEmpty {
                ContentUnavailableView {
                    Label("Nothing deleted", systemImage: "trash.slash")
                } description: {
                    Text("Anything you delete lands here first, and stays until you restore it or delete it forever.")
                }
            }

            if !games.isEmpty {
                Section("Games") {
                    ForEach(games) { game in
                        row(name: game.name,
                            detail: deletedLine(game.deletedAt),
                            cover: game.coverURLString) {
                            repo.restore(game)
                            reload()
                        } forever: {
                            confirmingForever = .game(game)
                        }
                    }
                }
            }
            if !playthroughs.isEmpty {
                Section("Playthroughs") {
                    ForEach(playthroughs) { pt in
                        row(name: pt.name,
                            detail: "\(pt.game?.name ?? "?") · \(deletedLine(pt.deletedAt))",
                            cover: pt.game?.coverURLString) {
                            repo.restore(pt)
                            reload()
                        } forever: {
                            confirmingForever = .playthrough(pt)
                        }
                    }
                }
            }
            if !collections.isEmpty {
                Section("Collections") {
                    ForEach(collections) { collection in
                        row(name: collection.name,
                            detail: "\(collection.gameIDs.count) game\(collection.gameIDs.count == 1 ? "" : "s") · \(deletedLine(collection.deletedAt))",
                            cover: nil) {
                            repo.restore(collection)
                            reload()
                        } forever: {
                            confirmingForever = .collection(collection)
                        }
                    }
                }
            }
        }
        .navigationTitle("Recently Deleted")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear(perform: reload)
        .confirmationDialog(
            "Delete \"\(confirmingForever?.name ?? "")\" forever?",
            isPresented: Binding(get: { confirmingForever != nil },
                                 set: { if !$0 { confirmingForever = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Forever", role: .destructive) {
                switch confirmingForever {
                case .game(let g): repo.deleteForever(g)
                case .playthrough(let p): repo.deleteForever(p)
                case .collection(let c): repo.deleteForever(c)
                case nil: break
                }
                confirmingForever = nil
                reload()
            }
            Button("Cancel", role: .cancel) { confirmingForever = nil }
        } message: {
            Text("Gone from every device, sessions and progress included. This is the only delete in the app that can't be undone.")
        }
    }

    private func row(name: String, detail: String, cover: String?,
                     restore: @escaping () -> Void,
                     forever: @escaping () -> Void) -> some View {
        HStack(spacing: 11) {
            CoverThumb(urlString: cover)
                .frame(width: 34, height: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("Restore") { restore() }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.bordered)
                .tint(LSTheme.accent)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { forever() } label: {
                Label("Delete Forever", systemImage: "trash.slash")
            }
        }
        .contextMenu {
            Button { restore() } label: { Label("Restore", systemImage: "arrow.uturn.backward") }
            Button(role: .destructive) { forever() } label: {
                Label("Delete Forever", systemImage: "trash.slash")
            }
        }
    }

    private func deletedLine(_ date: Date?) -> String {
        guard let date else { return "deleted" }
        return "deleted \(date.formatted(.relative(presentation: .named)))"
    }

    private func reload() {
        games = repo.trashedGames()
        playthroughs = repo.trashedPlaythroughs()
        collections = repo.trashedCollections()
    }
}
