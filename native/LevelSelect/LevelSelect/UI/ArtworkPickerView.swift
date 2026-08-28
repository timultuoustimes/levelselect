import SwiftUI
import SwiftData
import PhotosUI

/// Choose what fills one artwork role — cover, logo, or backdrop.
///
/// The build 31 cover picker generalised. Three separate pickers would have
/// been three features that felt unrelated; naming the *role* keeps one
/// surface, and makes the user's own pictures a SOURCE inside it rather than
/// something bolted on beside it.
///
/// Sources offered, in the order they're useful:
///   1. **Your images** — anything already added to this game.
///   2. **Add a photo** — the picker, ingested and downscaled on the way in.
///   3. **From IGDB** — covers and artwork for this game, when it's matched.
///   4. **A pasted URL** — the escape hatch for art the app can't find.
///
/// Nothing here ever writes `coverURLString` or any other fetched field, so a
/// metadata refresh or a Fix Match can't stomp a choice, and "Use the default"
/// is always one tap.
struct ArtworkPickerView: View {
    @Bindable var game: Game
    let role: ArtworkRole

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var igdbCovers: [String] = []
    @State private var igdbArtworks: [String] = []
    @State private var igdbShots: [String] = []
    @State private var loadingIGDB = true
    @State private var customURL = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var importing = false
    @State private var importError: String?

    private var repo: Repository { Repository(context) }
    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 12)]

    private var isSet: Bool { game.pointer(for: role) != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    yourImages
                    addPhoto
                    if loadingIGDB {
                        ProgressView("Looking for art…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    } else {
                        igdbGalleries
                    }
                    pasteURL
                }
                .padding()
            }
            .navigationTitle("Choose \(role.label)")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await loadIGDB() }
            .task(id: photoItem) { await ingestPickedPhoto() }
        }
    }

    // MARK: Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(role.fallbackNote)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if isSet {
                Button {
                    choose(nil)
                } label: {
                    Label("Use the default", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
            }
            if let importError {
                Text(importError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var yourImages: some View {
        let mine = game.liveImages
        if !mine.isEmpty {
            section("Your images") {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(mine) { image in
                        if let data = image.data {
                            Button { choose(image.pointer) } label: {
                                LocalArtworkThumb(data: data)
                                    .frame(width: 96, height: 128)
                                    .clipShape(.rect(cornerRadius: 8))
                                    .overlay { selectionBorder(pointer: image.pointer) }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(image.caption ?? "Your image")
                            .contextMenu {
                                Button(role: .destructive) {
                                    repo.softDelete(image)
                                } label: { Label("Remove", systemImage: "trash") }
                            }
                        }
                    }
                }
            }
        }
    }

    private var addPhoto: some View {
        PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
            if importing {
                HStack { ProgressView(); Text("Adding…") }
            } else {
                Label("Add a photo", systemImage: "photo.badge.plus")
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(importing)
    }

    @ViewBuilder
    private var igdbGalleries: some View {
        // Which IGDB art suits which role: a portrait cover is wrong behind a
        // header, and a 16:9 artwork is wrong on a shelf.
        switch role {
        case .cover:
            gallery("Covers from IGDB", ids: igdbCovers, size: "t_cover_big", aspect: 0.75)
            gallery("Artwork", ids: igdbArtworks, size: "t_720p", aspect: 1.78)
        case .backdrop:
            gallery("Artwork", ids: igdbArtworks, size: "t_720p", aspect: 1.78)
            gallery("Screenshots", ids: igdbShots, size: "t_screenshot_med", aspect: 1.78)
        case .logo:
            // IGDB has no logo type at all — the honest answer is to say so
            // rather than offer covers as if they'd do.
            Text("IGDB doesn't publish logos. Add your own image above, or paste a URL below — the game's name shows as text until you do.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .gallery:
            EmptyView()
        }
    }

    private var pasteURL: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Or paste an image URL")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                TextField("https://…", text: $customURL)
                    .textFieldStyle(.roundedBorder)
                    #if !os(macOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
                Button("Use") { choose(customURL.trimmingCharacters(in: .whitespaces)) }
                    .buttonStyle(.bordered)
                    .disabled(!isUsableURL(customURL))
            }
        }
    }

    private func gallery(_ title: String, ids: [String], size: String,
                         aspect: CGFloat) -> some View {
        Group {
            if !ids.isEmpty {
                section(title) {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(ids, id: \.self) { imageID in
                            let url = igdbURL(imageID, size: size)
                            Button { choose(url) } label: {
                                CoverThumb(urlString: url)
                                    .frame(width: 96, height: 96 / aspect)
                                    .clipShape(.rect(cornerRadius: 8))
                                    .overlay { selectionBorder(pointer: url) }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(title) option")
                        }
                    }
                }
            }
        }
    }

    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }

    @ViewBuilder
    private func selectionBorder(pointer: String) -> some View {
        if game.pointer(for: role) == pointer {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(LSTheme.accent, lineWidth: 3)
        }
    }

    // MARK: Actions

    private func igdbURL(_ imageID: String, size: String) -> String {
        "https://images.igdb.com/igdb/image/upload/\(size)/\(imageID).jpg"
    }

    private func isUsableURL(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        return URL(string: trimmed)?.scheme?.hasPrefix("http") == true
    }

    private func choose(_ pointer: String?) {
        repo.setArtwork(pointer?.isEmpty == true ? nil : pointer, role: role, on: game)
        dismiss()
    }

    private func ingestPickedPhoto() async {
        guard let photoItem else { return }
        importing = true
        importError = nil
        defer { importing = false; self.photoItem = nil }
        do {
            guard let raw = try await photoItem.loadTransferable(type: Data.self) else {
                importError = "That photo couldn't be read."
                return
            }
            // Added AND selected: someone who picks a photo while choosing a
            // cover means "use this one." Leaving it merely added would be a
            // second step nobody asked for.
            let image = try repo.addImage(to: game, data: raw, role: role)
            repo.setArtwork(image.pointer, role: role, on: game)
            dismiss()
        } catch ImageIngest.Failure.unreadable {
            importError = "That file isn't an image this device can read."
        } catch {
            importError = "Couldn't add that image."
        }
    }

    private func loadIGDB() async {
        defer { loadingIGDB = false }
        guard let igdbID = game.igdbID, role != .logo else { return }
        async let covers = IGDBService.raw(
            endpoint: "covers", query: "fields image_id; where game = \(igdbID); limit 50;")
        async let artworks = IGDBService.raw(
            endpoint: "artworks", query: "fields image_id; where game = \(igdbID); limit 50;")
        async let shots = IGDBService.raw(
            endpoint: "screenshots", query: "fields image_id; where game = \(igdbID); limit 30;")
        igdbCovers = (await covers).compactMap { $0["image_id"] as? String }
        igdbArtworks = (await artworks).compactMap { $0["image_id"] as? String }
        igdbShots = (await shots).compactMap { $0["image_id"] as? String }
    }
}

/// Draws a resolved role — remote, local, or nothing — so views don't each
/// re-derive "URL or Data or neither".
struct ArtworkView: View {
    let artwork: ResolvedArtwork
    var contentMode: ContentMode = .fill

    init(_ artwork: ResolvedArtwork, contentMode: ContentMode = .fill) {
        self.artwork = artwork
        self.contentMode = contentMode
    }

    var body: some View {
        switch artwork {
        case .local(let data):
            LocalArtworkThumb(data: data, contentMode: contentMode)
        case .remote(let url):
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    image.resizable().aspectRatio(contentMode: contentMode)
                } else {
                    Color.clear
                }
            }
        case .none:
            Color.clear
        }
    }
}

/// Draws bytes held in the store. Separate from `CoverThumb` (which takes a
/// URL and goes through AsyncImage) because local data needs no loading state
/// and no cache.
struct LocalArtworkThumb: View {
    let data: Data
    var contentMode: ContentMode = .fill

    var body: some View {
        if let image = PlatformImage(data: data) {
            image.resizable().aspectRatio(contentMode: contentMode)
        } else {
            Rectangle().fill(.quaternary)
        }
    }
}

/// `Image(uiImage:)` / `Image(nsImage:)` behind one name, so views don't
/// carry `#if os(macOS)` for something this small.
func PlatformImage(data: Data) -> Image? {
    #if os(macOS)
    guard let native = NSImage(data: data) else { return nil }
    return Image(nsImage: native)
    #else
    guard let native = UIImage(data: data) else { return nil }
    return Image(uiImage: native)
    #endif
}
