import SwiftUI
import SwiftData

/// Recently Deleted — the way back.
///
/// Deletion has been soft everywhere since V1, but "recoverable in principle"
/// with no recovery UI is a promise the app was keeping to itself. This
/// screen makes it real: everything deliberately deleted — games,
/// playthroughs, collections, pictures — listed with a Restore that is one
/// tap and a Delete Forever that is the app's ONLY hard delete, behind its
/// only double-confirmation.
///
/// **Pictures were the hole.** They were tombstoned like everything else and
/// then had nowhere to go: `restore(_ image:)` existed and nothing called it,
/// so a removed picture was invisible, unrecoverable, missing from the app's
/// own "Space used" figure, and still holding its full-size bytes on the
/// device and in iCloud. The only thing that ever freed them was deleting a
/// whole game forever — which does nothing at all for a picture on a memory
/// with no game. Tim: *"Photos need to show up in recently deleted and have a
/// way to be actually deleted."*
///
/// **Thirty days**, the number Photos, Files, Mail and Notes all use, so
/// nobody has to learn a new contract. This screen shipped with no window at
/// all and a comment saying a retention policy was "a decision to make with
/// testers, not a default to guess at" — which was true, and then went
/// undecided for ten builds. Tim decided it: *"I don't see why we have to
/// have an endless buildup of data that they already said they wanted to
/// delete. Especially because this is in their personal iCloud."* The sweep
/// is `Repository.purgeExpiredTrash`, run on foreground.
struct RecentlyDeletedView: View {
    @Environment(\.modelContext) private var context

    /// Local mirror refreshed on every change we make — @Query can't filter
    /// on "deletedAt != nil" alongside the repository's sorting cheaply, and
    /// this screen is transient enough that fetch-on-appear is honest.
    @State private var games: [Game] = []
    @State private var playthroughs: [Playthrough] = []
    @State private var collections: [GameCollection] = []
    @State private var images: [GameImage] = []
    @State private var confirmingForever: ForeverTarget?

    private var repo: Repository { Repository(context) }

    enum ForeverTarget: Identifiable {
        case game(Game), playthrough(Playthrough), collection(GameCollection)
        case image(GameImage)
        var id: UUID {
            switch self {
            case .game(let g): g.id
            case .playthrough(let p): p.id
            case .collection(let c): c.id
            case .image(let i): i.id
            }
        }
        var name: String {
            switch self {
            case .game(let g): g.name
            case .playthrough(let p): p.name
            case .collection(let c): c.name
            // Inline rather than calling the view's helper: crossing out of
            // this nonisolated accessor with a model object is a data race
            // the compiler is right to refuse.
            case .image(let i):
                {
                    let caption = (i.caption ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !caption.isEmpty { return caption }
                    if let game = i.game { return game.name }
                    let title = i.memory?.title
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    return title.isEmpty ? "Picture" : title
                }()
            }
        }
        /// A game takes its sessions with it; a picture takes a file. Saying
        /// which is what makes a permanent delete an informed one.
        var warning: String {
            switch self {
            case .image:
                "The picture and its file are removed from this device and from iCloud. This is the only delete in the app that can't be undone."
            default:
                "Gone from every device, sessions and progress included. This is the only delete in the app that can't be undone."
            }
        }
    }

    /// What to call a removed picture. Its own caption if it has one, then
    /// what it was a picture OF, then the honest generic.
    func title(for image: GameImage) -> String {
        let caption = (image.caption ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !caption.isEmpty { return caption }
        if let game = image.game { return game.name }
        let memoryTitle = image.memory?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !memoryTitle.isEmpty { return memoryTitle }
        return "Picture"
    }

    var body: some View {
        List {
            if games.isEmpty && playthroughs.isEmpty && collections.isEmpty
                && images.isEmpty {
                ContentUnavailableView {
                    Label("Nothing deleted", systemImage: "trash.slash")
                } description: {
                    Text("Anything you delete lands here first and stays for 30 days, unless you restore it or delete it forever sooner.")
                }
            } else {
                // **The clock is running on THIS screen, so it says so here.**
                //
                // The thirty days were promised on the delete confirmation and
                // then never mentioned again. Someone who arrives from
                // Settings a week later — which is the whole reason this
                // screen exists — had no way to know anything was counting
                // down, or how to end it early. Fable, 2026-09-07.
                Section {
                    EmptyView()
                } footer: {
                    Text("Everything here is kept for 30 days from when you deleted it, then goes on its own. Swipe a row or press and hold to restore it, or to delete it forever now.")
                }
            }

            if !games.isEmpty {
                Section("Games") {
                    ForEach(games) { game in
                        row(name: game.name,
                            detail: deletedLine(game.deletedAt),
                            cover: game.displayCoverURLString,
                            artwork: game.resolvedArtwork(.cover)) {
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
                            cover: pt.game?.displayCoverURLString,
                            artwork: pt.game?.resolvedArtwork(.cover)) {
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
            if !images.isEmpty {
                Section {
                    ForEach(images) { image in
                        imageRow(image)
                    }
                } header: {
                    Text("Pictures")
                } footer: {
                    // The one number the app was getting wrong: Settings →
                    // Library → Game images counts live pictures only, so
                    // these were costing space nothing reported.
                    Text("\(images.count) removed \(images.count == 1 ? "picture is" : "pictures are") still using \(ImageIngest.formattedBytes(images.reduce(0) { $0 + $1.byteCount })), here and in iCloud. They free themselves after 30 days.")
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
                case .image(let i): repo.deleteForever(i)
                case nil: break
                }
                confirmingForever = nil
                reload()
            }
            Button("Cancel", role: .cancel) { confirmingForever = nil }
        } message: {
            Text(confirmingForever?.warning
                 ?? "This is the only delete in the app that can't be undone.")
        }
    }

    /// Its own thumbnail rather than a cover: a picture is the thing itself,
    /// and two removed pictures from one game would otherwise look identical.
    private func imageRow(_ image: GameImage) -> some View {
        HStack(spacing: 11) {
            Group {
                if let data = image.data {
                    LocalArtworkThumb(data: data)
                } else {
                    // A row that arrived from sync before its asset did.
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(LSTheme.cardFill)
                }
            }
            .frame(width: 46, height: 46)
            .clipShape(.rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(title(for: image))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(imageDetail(image))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("Restore") {
                repo.restore(image)
                reload()
            }
            .font(.footnote.weight(.semibold))
            .buttonStyle(.bordered)
            .tint(LSTheme.accent)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { confirmingForever = .image(image) } label: {
                Label("Delete Forever", systemImage: "trash.slash")
            }
            // The row tints its Restore button with the accent, and the swipe
            // action inherited it — so the app's only hard delete arrived in
            // the same colour as the button that puts things back. Fable saw
            // it as "tinted in the accent blue rather than red".
            .tint(.red)
        }
        .contextMenu {
            Button {
                repo.restore(image)
                reload()
            } label: { Label("Restore", systemImage: "arrow.uturn.backward") }
            Button(role: .destructive) { confirmingForever = .image(image) } label: {
                Label("Delete Forever", systemImage: "trash.slash")
            }
        }
    }

    /// Where it came from, what it costs, and when it went — a removed
    /// picture is hard to recognize from a thumbnail alone.
    private func imageDetail(_ image: GameImage) -> String {
        var parts: [String] = []
        if let game = image.game {
            parts.append(game.name)
        } else if let memory = image.memory {
            let title = memory.title.trimmingCharacters(in: .whitespacesAndNewlines)
            parts.append(title.isEmpty ? "a memory" : title)
        }
        parts.append(ImageIngest.formattedBytes(image.byteCount))
        parts.append(deletedLine(image.deletedAt))
        return parts.joined(separator: " · ")
    }

    private func row(name: String, detail: String, cover: String?,
                     artwork: ResolvedArtwork? = nil,
                     restore: @escaping () -> Void,
                     forever: @escaping () -> Void) -> some View {
        HStack(spacing: 11) {
            // A cover you picked from Photos has no URL by design, so this
            // drew a generic controller for a game every shelf was drawing
            // properly. Fable, 2026-09-07.
            CoverThumb(urlString: cover, artwork: artwork)
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
            .tint(.red)
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
        images = repo.trashedImages()
    }
}
