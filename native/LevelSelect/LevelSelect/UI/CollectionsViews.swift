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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up.fill")
                    .foregroundStyle(LSTheme.accent)
                Text("Collections").font(.title3.bold())
                Text("(\(collections.count))")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Button { onNew() } label: {
                    Image(systemName: "plus").font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(LSTheme.accent)
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

    private var repo: Repository { Repository(context) }

    private var visible: [Game] {
        search.isEmpty ? allGames
            : allGames.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(visible) { game in
                    Button {
                        repo.setMembership(collection, game: game, member: !collection.contains(game))
                    } label: {
                        HStack(spacing: 12) {
                            CoverThumb(urlString: game.coverURLString)
                                .frame(width: 40, height: 53)
                            Text(game.name).font(.subheadline)
                            Spacer()
                            Image(systemName: collection.contains(game) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(collection.contains(game) ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
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
        }
    }
}
