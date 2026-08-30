import SwiftUI
import SwiftData

/// Pick an avatar out of the art of a game you actually play.
///
/// This replaced a picker built on IGDB's `characters` endpoint. The coverage
/// wasn't there: character records are mostly text, and isolated portraits are
/// the exception. Artwork is the opposite — Mina has eleven, Hades fourteen —
/// and it is already fetched, already allowlisted on the proxy, and already
/// how covers and backdrops work.
///
/// Sourced from YOUR library rather than a global search, which is both a
/// smaller thing to build and a better default: an avatar taken from a game
/// on your own shelf says something, and a global search is one more empty
/// text field to face.
struct AvatarArtworkPicker: View {
    /// Raw downloaded bytes — the caller decides about cropping.
    var onPick: (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Game> { $0.deletedAt == nil }, sort: \Game.name)
    private var games: [Game]

    @State private var term = ""
    @State private var chosen: Game?

    private var matches: [Game] {
        let q = term.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return games }
        return games.filter { $0.name.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            List(matches) { game in
                Button { chosen = game } label: {
                    HStack(spacing: 12) {
                        CoverThumb(urlString: game.displayCoverURLString)
                            .frame(width: 34, height: 45)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        Text(game.name).foregroundStyle(.primary)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $term, prompt: "Find a game")
            .navigationTitle("Choose a game")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .navigationDestination(item: $chosen) { game in
                // No `dismiss()` here on purpose. The editor owns which sheet
                // is up: an opaque image swaps this sheet for the positioning
                // one, and dismissing first would nil the binding the editor
                // had just set, so the crop step would never appear.
                GameArtGrid(game: game, onPick: onPick)
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 560)
        #endif
    }
}

/// Every piece of art one game has, at avatar scale.
private struct GameArtGrid: View {
    let game: Game
    var onPick: (Data) -> Void

    @State private var imageIDs: [String] = []
    @State private var sgdb: [SteamGridDBService.Artwork] = []
    @State private var loading = true
    @State private var downloading: String?
    @State private var message: String?

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 10)]

    var body: some View {
        ScrollView {
            if loading {
                ProgressView().padding(.top, 60)
            } else if imageIDs.isEmpty && sgdb.isEmpty {
                ContentUnavailableView("No artwork for this game",
                                       systemImage: "photo.on.rectangle")
                    .padding(.top, 40)
            }

            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(LSTheme.working)
                    .padding(.horizontal)
            }

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(imageIDs, id: \.self) { id in
                    // PNG: an IGDB artwork can carry alpha, and `.jpg` would
                    // flatten it onto black before anyone got to choose.
                    tile(url: URL(string:
                        "https://images.igdb.com/igdb/image/upload/t_720p/\(id).png"), key: id)
                }
                ForEach(sgdb) { art in
                    // Thumb in the grid, full only once chosen — the full hero
                    // is about fifteen times the bytes for the same picture.
                    tile(url: URL(string: art.thumb), key: art.full,
                         download: URL(string: art.full))
                }
            }
            .padding()
        }
        .navigationTitle(game.name)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await load() }
    }

    private func tile(url: URL?, key: String, download: URL? = nil) -> some View {
        Button { Task { await grab(download ?? url, key: key) } } label: {
            // `Color.clear` sets the cell's shape and the image fills it from
            // behind. Constraining only the HEIGHT of a `.fill` image leaves
            // its width intrinsic, so a wide SteamGridDB hero grew past its
            // grid cell and painted over its neighbours — `clipShape` hides
            // pixels but does not shrink the layout.
            ZStack {
                Color.clear
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay {
                        AsyncImage(url: url) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Rectangle().fill(.quaternary)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                if downloading == key { ProgressView() }
            }
        }
        .buttonStyle(.plain)
        .disabled(downloading != nil)
    }

    private func load() async {
        defer { loading = false }
        if let igdbID = game.igdbID {
            let rows = await IGDBService.raw(
                endpoint: "artworks",
                query: "fields image_id,image_type; where game = \(igdbID); limit 50;")
            // Logos excluded: a wordmark is a poor avatar and there is already
            // a place to choose one on the game page.
            imageIDs = rows
                .filter { !IGDBImageType.logos.contains($0["image_type"] as? Int ?? 0) }
                .compactMap { $0["image_id"] as? String }
        }
        sgdb = await SteamGridDBService.artwork(for: game, role: .backdrop) ?? []
    }

    private func grab(_ url: URL?, key: String) async {
        guard let url else { return }
        downloading = key
        defer { downloading = nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            onPick(data)
        } catch {
            message = "That image couldn't be downloaded. Try another."
        }
    }
}
