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
        AsyncImage(url: game.coverURLString.flatMap(URL.init(string:))) { phase in
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
                            .background(.ultraThinMaterial, in: .circle)
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
                            Label("Start from a Prompt", systemImage: "sparkles.rectangle.stack")
                        }
                        Button { onNew() } label: {
                            Label("Empty Collection", systemImage: "square.stack")
                        }
                    } label: {
                        Image(systemName: "plus").font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(LSTheme.accent)
                } else {
                    Button { onNew() } label: {
                        Image(systemName: "plus").font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(LSTheme.accent)
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
            statusBar
            List {
                if visible.isEmpty {
                    Text(status == nil
                         ? "No games match that search."
                         : "Nothing in your library is \(status!.sectionTitle) right now.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
                ForEach(visible) { game in
                    let isMember = members.contains(game.id.uuidString)
                    Button {
                        repo.setMembership(collection, game: game, member: !isMember)
                    } label: {
                        HStack(spacing: 12) {
                            CoverThumb(urlString: game.coverURLString)
                                .frame(width: 40, height: 53)
                            Text(game.name).font(.subheadline)
                            Spacer()
                            Image(systemName: isMember ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isMember ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
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
