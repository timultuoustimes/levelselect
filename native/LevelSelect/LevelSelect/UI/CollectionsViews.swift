import SwiftUI
import SwiftData

/// Navigation target for a collection.
struct CollectionRoute: Hashable { let id: UUID }

// MARK: - Cover mosaic

/// Up to 4 member covers in a 2×2 (or a single cover / placeholder).
struct CoverMosaic: View {
    let games: [Game]

    var body: some View {
        let covers = Array(games.prefix(4))
        ZStack {
            Rectangle().fill(.white.opacity(0.05))
            switch covers.count {
            case 0:
                Image(systemName: "square.stack.3d.up")
                    .font(.title)
                    .foregroundStyle(.secondary)
            case 1:
                tile(covers[0])
            default:
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)],
                          spacing: 2) {
                    ForEach(covers) { tile($0).aspectRatio(1, contentMode: .fill).clipped() }
                }
            }
        }
    }

    private func tile(_ game: Game) -> some View {
        AsyncImage(url: game.displayCoverURLString.flatMap(URL.init(string:))) { phase in
            switch phase {
            case .success(let img): img.resizable().scaledToFill()
            default: Rectangle().fill(.white.opacity(0.06))
            }
        }
    }
}

// MARK: - Shelf + card

struct CollectionCard: View {
    let collection: GameCollection
    let members: [Game]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverMosaic(games: members)
                .frame(width: 122, height: 122)
                .clipShape(.rect(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.08)))
                .overlay(alignment: .topTrailing) {
                    if collection.isBundle {
                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: 9))
                            .padding(5)
                            .glassEffect(.regular, in: .circle)
                            .padding(5)
                    }
                }
                .shadow(color: .black.opacity(0.4), radius: 5, y: 3)
            Text(collection.name)
                .font(.footnote.weight(.medium))
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
            Text("\(members.count) game\(members.count == 1 ? "" : "s")")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 122, alignment: .leading)
    }
}

struct CollectionShelf: View {
    let collections: [GameCollection]
    let games: [Game]
    var onNew: () -> Void
    var onNewFromTemplate: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up.fill")
                    .foregroundStyle(LSTheme.accent)
                Text("Collections").font(.title3.bold())
                Text("(\(collections.count))")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                // Both routes, because this "+" was the only one and it went
                // straight to a name field — which asks you to have already
                // had the idea, and hides the half of the feature that
                // supplies one.
                if let onNewFromTemplate {
                    Menu {
                        Button { onNewFromTemplate() } label: {
                            // Same wording as the Library toolbar. "Start from
                            // a Prompt" repeated the "template of WHAT?"
                            // problem the rename was meant to end.
                            Label("Collection from a Prompt", systemImage: "sparkles.rectangle.stack")
                        }
                        Button { onNew() } label: {
                            Label("Empty Collection", systemImage: "square.stack")
                        }
                    } label: {
                        Image(systemName: "plus").font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(LSTheme.accent)
                    .accessibilityLabel("Add collection")
                } else {
                    Button { onNew() } label: {
                        Image(systemName: "plus").font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(LSTheme.accent)
                    .accessibilityLabel("Add collection")
                }
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(collections) { collection in
                        NavigationLink(value: CollectionRoute(id: collection.id)) {
                            CollectionCard(collection: collection, members: members(of: collection))
                        }
                        .buttonStyle(PressableCardStyle())
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func members(of collection: GameCollection) -> [Game] {
        let ids = Set(collection.gameIDs)
        return games.filter { ids.contains($0.id.uuidString) }
    }
}

// MARK: - Detail

struct CollectionDetailView: View {
    @Bindable var collection: GameCollection
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<Game> { $0.deletedAt == nil }, sort: \Game.name)
    private var allGames: [Game]

    @State private var renaming = false
    @State private var nameField = ""
    @State private var pickingMembers = false
    @State private var confirmingDelete = false

    private var repo: Repository { Repository(context) }

    private var members: [Game] {
        let ids = Set(collection.gameIDs)
        return allGames.filter { ids.contains($0.id.uuidString) }
    }

    var body: some View {
        ScrollView {
            if members.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 40)).foregroundStyle(.secondary)
                    Text("No games yet").foregroundStyle(.secondary)
                    Button("Add Games") { pickingMembers = true }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity).padding(.top, 60)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), spacing: 12)], spacing: 16) {
                    ForEach(members) { game in
                        NavigationLink(value: game) {
                            LibraryGridCell(game: game, size: .medium)
                        }
                        .buttonStyle(PressableCardStyle())
                        .gameContextMenu(game)
                    }
                }
                .padding()
            }
        }
        .scrollIndicators(.hidden)
        // Soft, not the default `.hard`. See RootView: iOS 26's scroll edge
        // effect draws a crisp line where content meets a bar unless told
        // otherwise, and one screen fading while the rest cut is worse than
        // either done consistently.
        .scrollEdgeEffectStyle(.soft, for: .top)
        .lsBackground()
        .navigationTitle(collection.name)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        pickingMembers = true
                    } label: { Label("Add / Remove Games…", systemImage: "plus.square.on.square") }
                    Button {
                        nameField = collection.name; renaming = true
                    } label: { Label("Rename…", systemImage: "pencil") }
                    Toggle(isOn: Binding(
                        get: { collection.isBundle },
                        set: { repo.setBundle(collection, isBundle: $0) })
                    ) { Label("Bundle (hide members in library)", systemImage: "shippingbox") }
                    Divider()
                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: { Label("Delete Collection", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Collection actions")
            }
        }
        .sheet(isPresented: $pickingMembers) {
            CollectionMembersPicker(collection: collection)
        }
        .alert("Rename Collection", isPresented: $renaming) {
            TextField("Name", text: $nameField)
            Button("Save") {
                let n = nameField.trimmingCharacters(in: .whitespaces)
                if !n.isEmpty { repo.renameCollection(collection, to: n) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete “\(collection.name)”?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Collection", role: .destructive) {
                repo.deleteCollection(collection)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The games stay in your library — only the collection is removed.")
        }
    }
}

// MARK: - Members picker

struct CollectionMembersPicker: View {
    @Bindable var collection: GameCollection
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<Game> { $0.deletedAt == nil }, sort: \Game.name)
    private var allGames: [Game]
    @State private var search = ""
    /// nil = every game. Starts on whatever the collection's prompt implies,
    /// so a list about the backlog doesn't open onto the whole library and
    /// make you do the filtering the prompt already did.
    @State private var status: GameStatus?
    @State private var appliedDefault = false
    /// Grows with the reader's text size, so accessibility sizes get fewer,
    /// wider cells instead of the same narrow columns with more clipping.
    @ScaledMetric(relativeTo: .caption2) private var cellWidth: CGFloat = 105

    private var repo: Repository { Repository(context) }

    private var visible: [Game] {
        allGames.filter { game in
            if let status, game.status != status { return false }
            guard !search.isEmpty else { return true }
            return game.name.localizedCaseInsensitiveContains(search)
        }
    }

    /// Statuses worth offering: the ones the library actually contains, in the
    /// app's own order. A filter for a status with nothing in it is a dead end.
    private var statusChoices: [GameStatus] {
        let present = Set(allGames.map(\.status))
        return GameStatus.displayOrder.filter { present.contains($0) }
    }

    private var statusBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(nil, label: "All")
                ForEach(statusChoices, id: \.self) { chip($0, label: $0.sectionTitle) }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    /// Cover art with the selection on the art itself.
    ///
    /// The old row was a 40pt thumbnail, a name, and a dot at the far right —
    /// three glances to answer "is this one in?". Box art is how anyone
    /// actually recognises a game, and a ring around it answers the question
    /// in the same look.
    private func cell(_ game: Game, selected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            CoverThumb(urlString: game.displayCoverURLString)
                .aspectRatio(3 / 4, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(.rect(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(selected ? LSTheme.accent : .clear, lineWidth: 3))
                .overlay(alignment: .topTrailing) {
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.black, LSTheme.accent)
                            .padding(5)
                    }
                }
                // Unpicked art recedes, so the chosen ones read as a set at a
                // glance rather than needing to be counted.
                .opacity(selected ? 1 : 0.62)
            Text(game.name)
                .font(.caption2)
                .foregroundStyle(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// How many are in, against how many the prompt asked for.
    ///
    /// A count the prompt names is useless if you can't see it while choosing —
    /// "pick six" and then no sixes anywhere. Over the target is stated plainly
    /// rather than blocked: the number was always a prompt, not a limit.
    @ViewBuilder
    private var tally: some View {
        let picked = collection.gameIDs.count
        let target = CollectionTemplate.matching(collectionNamed: collection.name)?.slots
        HStack(spacing: 8) {
            if let target {
                Text("\(picked) of \(target)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(picked == target ? LSTheme.accent : .primary)
                if picked > target {
                    Text("over — that's allowed")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if picked < target {
                    Text("\(target - picked) to go")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(picked == 1 ? "1 game" : "\(picked) games")
                    .font(.headline.monospacedDigit())
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .animation(.snappy(duration: 0.2), value: picked)
    }

    private func chip(_ value: GameStatus?, label: String) -> some View {
        let selected = status == value
        return Button {
            status = value
        } label: {
            Text(label)
                .font(.caption.weight(selected ? .bold : .regular))
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(selected ? AnyShapeStyle(LSTheme.accent.opacity(0.25))
                                     : AnyShapeStyle(.white.opacity(0.06)),
                            in: .capsule)
                .overlay(Capsule().strokeBorder(
                    selected ? LSTheme.accent.opacity(0.55) : .white.opacity(0.08), lineWidth: 1))
                .foregroundStyle(selected ? AnyShapeStyle(LSTheme.accent) : AnyShapeStyle(.secondary))
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        // One Set, once per render. Membership is stored as an id array, and
        // three linear `contains` per row made a big library × big collection
        // picker roughly O(games × members).
        let members = Set(collection.gameIDs)
        NavigationStack {
            VStack(spacing: 0) {
                tally
                statusBar
                ScrollView {
                    if visible.isEmpty {
                        Text(status == nil
                             ? "No games match that search."
                             : "Nothing in your library is \(status!.sectionTitle) right now.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: cellWidth), spacing: 12)],
                              spacing: 14) {
                        ForEach(visible) { game in
                            let isMember = members.contains(game.id.uuidString)
                            Button {
                                repo.setMembership(collection, game: game, member: !isMember)
                            } label: {
                                cell(game, selected: isMember)
                            }
                            .buttonStyle(PressableCardStyle())
                        }
                    }
                    .padding()
                }
                .scrollIndicators(.hidden)
            }
            .lsBackground()
            .searchable(text: $search, prompt: "Search games")
            .navigationTitle(collection.name)
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                // Once per presentation, and only as a starting point: after
                // that the filter is the user's, including when they clear it.
                guard !appliedDefault else { return }
                appliedDefault = true
                status = CollectionTemplate.matching(collectionNamed: collection.name)?.picksFrom
            }
        }
    }
}

/// Resolve a CollectionRoute to its detail view — the launcher widget's
/// landing. LibraryView resolves inline against its own query; this is the
/// same resolution for stacks (Home) that don't hold one.
struct CollectionRouteView: View {
    let route: CollectionRoute
    @Query(filter: #Predicate<GameCollection> { $0.deletedAt == nil })
    private var collections: [GameCollection]

    var body: some View {
        if let collection = collections.first(where: { $0.id == route.id }) {
            CollectionDetailView(collection: collection)
        } else {
            ContentUnavailableView("Collection not found",
                                   systemImage: "square.stack.3d.up.slash")
        }
    }
}
