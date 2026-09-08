import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

/// The game page's Maps section: the maps this game has, and four ways to
/// get one. A map is a picture in the library (see `MapsRepository`), so
/// the Photo Library and Files paths are the ones pictures already use; Paste
/// takes an image off the clipboard; Find asks `map-finder`, which the web
/// app used and which has stayed deployed.
struct MapsSection: View {
    let game: Game
    @Environment(\.modelContext) private var context

    @State private var viewing: MapViewerTarget?
    @State private var photoItem: PhotosPickerItem?
    /// A `PhotosPicker` INSIDE a `Menu` never presents — the menu dismisses
    /// and the picker's presentation goes with it. Tim, 09-08: *"tapping add
    /// map from photo library doesn't open the photo picker."* The menu item
    /// is a button, and the picker is a modifier on the section.
    @State private var choosingPhoto = false
    @State private var choosingFile = false
    @State private var finding = false
    @State private var naming: PendingMap?
    @State private var error: String?

    private var repo: Repository { Repository(context) }
    private var maps: [GameMap] { repo.liveMaps(of: game) }

    /// Bytes picked, waiting for a name and a kind.
    struct PendingMap: Identifiable {
        let id = UUID()
        var data: Data
        var suggestedName: String
        var kind: MapKind
        var sourceURL: String?
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !maps.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(maps) { map in
                            Button { viewing = MapViewerTarget(game: game, map: map) } label: {
                                thumb(map)
                            }
                            .buttonStyle(PressableCardStyle())
                        }
                    }
                }
            }
            addMenu
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .lsFullScreen(item: $viewing) { target in
            MapViewerView(target: target)
        }
        .sheet(item: $naming) { pending in
            NameMapSheet(pending: pending) { name, kind in
                do {
                    try repo.addMap(to: game, data: pending.data, name: name, kind: kind,
                                    sourceURL: pending.sourceURL)
                    error = nil
                } catch ImageIngest.Failure.unreadable {
                    error = "That file isn't an image this device can read."
                } catch {
                    self.error = "Couldn't add that map."
                }
            }
            .lsSheet()
        }
        .sheet(isPresented: $finding) {
            MapFinderSheet(gameName: game.name) { data, suggestion in
                naming = PendingMap(data: data, suggestedName: suggestion.name,
                                    kind: suggestion.kind, sourceURL: suggestion.url)
            }
            .lsSheet([.large])
        }
        .photosPicker(isPresented: $choosingPhoto, selection: $photoItem,
                      matching: .images, photoLibrary: .shared())
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                defer { photoItem = nil }
                if let data = try? await item.loadTransferable(type: Data.self) {
                    naming = PendingMap(data: data, suggestedName: defaultName, kind: defaultKind)
                } else {
                    error = "That photo couldn't be read."
                }
            }
        }
        .fileImporter(isPresented: $choosingFile,
                      allowedContentTypes: [.png, .jpeg, .heic, .webP, .image],
                      allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) {
                naming = PendingMap(data: data,
                                    suggestedName: url.deletingPathExtension().lastPathComponent,
                                    kind: defaultKind)
            } else {
                error = "Couldn't read that file."
            }
        }
    }

    private var defaultName: String { maps.isEmpty ? "World" : "Area \(maps.count)" }
    private var defaultKind: MapKind { maps.isEmpty ? .world : .area }

    private func thumb(_ map: GameMap) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if let image = repo.image(for: map), let data = image.data {
                    LocalArtworkThumb(data: data)
                } else {
                    ZStack {
                        LSTheme.cardFill
                        Image(systemName: "map").foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 150, height: 96)
            .clipShape(.rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(LSTheme.hairline))
            Text(map.name)
                .font(.caption.weight(.medium))
                .lineLimit(1)
            let live = repo.liveMarkers(of: map)
            Text(live.isEmpty ? map.kind.label
                 : "\(map.kind.label) · \(live.count) pin\(live.count == 1 ? "" : "s")")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 150, alignment: .leading)
    }

    private var addMenu: some View {
        Menu {
            Button { choosingPhoto = true } label: {
                Label("Photo Library", systemImage: "photo.on.rectangle")
            }
            Button { choosingFile = true } label: {
                Label("Files", systemImage: "folder")
            }
            Button { paste() } label: {
                Label("Paste an Image", systemImage: "doc.on.clipboard")
            }
            Divider()
            Button { finding = true } label: {
                Label("Find One…", systemImage: "sparkles")
            }
        } label: {
            Label(maps.isEmpty ? "Add a map" : "Add another map", systemImage: "plus")
                .font(.subheadline.weight(.medium))
        }
        .buttonStyle(.bordered)
        .tint(LSTheme.accent)
    }

    private func paste() {
        #if os(macOS)
        let data = NSPasteboard.general.data(forType: .png)
            ?? NSPasteboard.general.data(forType: .tiff)
        #else
        let data = UIPasteboard.general.image?.pngData()
        #endif
        if let data {
            naming = PendingMap(data: data, suggestedName: defaultName, kind: defaultKind)
        } else {
            error = "Nothing on the clipboard is an image."
        }
    }
}

/// Name it, say what kind it is, keep it.
struct NameMapSheet: View {
    let pending: MapsSection.PendingMap
    var onKeep: (String, MapKind) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind: MapKind = .other

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let image = PlatformImage(data: pending.data) {
                        image.resizable().scaledToFit()
                            .frame(maxHeight: 180)
                            .clipShape(.rect(cornerRadius: 10))
                            .frame(maxWidth: .infinity)
                    }
                }
                Section {
                    TextField("Name", text: $name)
                    Picker("Kind", selection: $kind) {
                        ForEach([MapKind.world, .area, .other], id: \.self) { k in
                            Text(k.label).tag(k)
                        }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(pending.sourceURL.flatMap { URL(string: $0)?.host() }.map { "From \($0). The site is kept with the map." }
                         ?? "Maps are pictures in your library: they sync with it, go to Recently Deleted, and come with an export.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add a map")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Keep") { onKeep(name.isEmpty ? pending.suggestedName : name, kind); dismiss() }
                }
            }
        }
        .onAppear { name = pending.suggestedName; kind = pending.kind }
    }
}

/// "Find one": what the web turned up, with where each came from.
struct MapFinderSheet: View {
    let gameName: String
    var onPick: (Data, MapFinderService.Suggestion) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var pageURL = ""
    @State private var suggestions: [MapFinderService.Suggestion] = []
    @State private var searching = false
    @State private var fetching: String?
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("A wiki page with maps (optional)", text: $pageURL)
                            .textContentType(.URL)
                            #if !os(macOS)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled()
                        Button(searching ? "Searching…" : "Search") { Task { await search() } }
                            .disabled(searching)
                    }
                } footer: {
                    Text("Searches the web for \(gameName) maps — game wikis first. Nothing is kept until you pick one, and the site it came from stays with the map.")
                }
                if let problem {
                    Section { Text(problem).foregroundStyle(.secondary) }
                }
                if !suggestions.isEmpty {
                    Section("Found") {
                        ForEach(suggestions) { s in
                            Button { Task { await keep(s) } } label: {
                                HStack(spacing: 12) {
                                    FoundMapThumb(url: s.url)
                                        .frame(width: 84, height: 56)
                                        .clipShape(.rect(cornerRadius: 8))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(s.name).font(.subheadline).lineLimit(2)
                                        Text("\(s.kind.label) · \(s.source)")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if fetching == s.id { ProgressView() }
                                }
                            }
                            .tint(.primary)
                            .disabled(fetching != nil)
                        }
                    }
                }
            }
            .navigationTitle("Find a map")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .task { await search() }
    }

    private func search() async {
        searching = true; problem = nil
        defer { searching = false }
        do {
            suggestions = try await MapFinderService.find(gameName: gameName,
                                                          pageURL: pageURL.isEmpty ? nil : pageURL)
            if suggestions.isEmpty { problem = "Nothing found. Try a wiki page URL, or add one from Files." }
        } catch {
            problem = error.localizedDescription
        }
    }

    private func keep(_ s: MapFinderService.Suggestion) async {
        fetching = s.id
        defer { fetching = nil }
        do {
            let data = try await MapFinderService.download(s)
            onPick(data, s)
            dismiss()
        } catch {
            problem = error.localizedDescription
        }
    }
}

/// `fullScreenCover` where it exists; a sheet on the Mac, which has no such
/// thing and where a map in a window is the right shape anyway.
private struct FullScreenItem<Item: Identifiable, Sheet: View>: ViewModifier {
    @Binding var item: Item?
    let sheet: (Item) -> Sheet
    func body(content: Content) -> some View {
        #if os(macOS)
        content.sheet(item: $item) { sheet($0).frame(minWidth: 720, minHeight: 560) }
        #else
        content.fullScreenCover(item: $item) { sheet($0) }
        #endif
    }
}

extension View {
    func lsFullScreen<Item: Identifiable, Sheet: View>(
        item: Binding<Item?>, @ViewBuilder content: @escaping (Item) -> Sheet) -> some View {
        modifier(FullScreenItem(item: item, sheet: content))
    }
}


/// A result thumbnail, fetched with the same headers the download uses —
/// `AsyncImage` cannot send any, and a wiki CDN that refuses the download
/// refuses the preview the same way.
private struct FoundMapThumb: View {
    let url: String
    @State private var data: Data?
    @State private var failed = false

    var body: some View {
        ZStack {
            LSTheme.cardFill
            if let data, let image = PlatformImage(data: data) {
                image.resizable().scaledToFill()
            } else if failed {
                Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task(id: url) {
            guard let u = URL(string: url) else { failed = true; return }
            if let (bytes, response) = try? await URLSession.shared.data(for: MapFinderService.request(for: u)),
               (response as? HTTPURLResponse)?.statusCode == 200, !bytes.isEmpty {
                data = bytes
            } else {
                failed = true
            }
        }
    }
}
