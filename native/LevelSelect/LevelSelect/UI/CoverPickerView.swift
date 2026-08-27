import SwiftUI
import SwiftData

/// Pick a different cover — IGDB's alternates for this game, or any image URL
/// pasted in. Writes `coverOverrideURLString`; the fetched cover is never
/// touched, so "Use fetched cover" is always a safe way back and Fix Match /
/// the fill pass can't stomp a choice. The field shipped in Schema V2 for
/// exactly this ("the art the box had when THEY owned it"); this is the UI it
/// was waiting for.
struct CoverPickerView: View {
    @Bindable var game: Game
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var covers: [String] = []      // image ids
    @State private var artworks: [String] = []
    @State private var loading = true
    @State private var customURL = ""

    private var repo: Repository { Repository(context) }

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if game.coverOverrideURLString != nil {
                        Button {
                            choose(nil)
                        } label: {
                            Label("Use fetched cover", systemImage: "arrow.uturn.backward")
                        }
                        .buttonStyle(.bordered)
                    }

                    if loading {
                        ProgressView("Looking for alternates…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 30)
                    } else {
                        if !covers.isEmpty {
                            gallery("Covers", ids: covers, size: "t_cover_big")
                        }
                        if !artworks.isEmpty {
                            gallery("Artwork", ids: artworks, size: "t_720p")
                        }
                        if covers.isEmpty && artworks.isEmpty {
                            Text(game.igdbID == nil
                                 ? "This game isn't matched to IGDB, so there are no alternates to offer — paste an image URL below."
                                 : "IGDB has no alternate art for this game — paste an image URL below.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

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
                                .buttonStyle(.borderedProminent)
                                .disabled(URL(string: customURL.trimmingCharacters(in: .whitespaces))?.scheme?.hasPrefix("http") != true)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Change Cover")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private func gallery(_ title: String, ids: [String], size: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(ids, id: \.self) { imageID in
                    let url = "https://images.igdb.com/igdb/image/upload/\(size)/\(imageID).jpg"
                    Button {
                        choose(url)
                    } label: {
                        CoverThumb(urlString: url)
                            .frame(width: 92, height: 122)
                            .overlay {
                                if game.coverOverrideURLString == url {
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(LSTheme.accent, lineWidth: 3)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(title) option")
                }
            }
        }
    }

    /// nil clears the override (back to the fetched cover).
    private func choose(_ url: String?) {
        repo.edit(game) { $0.coverOverrideURLString = url?.isEmpty == true ? nil : url }
        dismiss()
    }

    private func load() async {
        defer { loading = false }
        guard let igdbID = game.igdbID else { return }
        // Two cheap allowlisted queries; the proxy already permits both
        // endpoints. Empty on failure — the paste field still works offline.
        async let coverRows = IGDBService.raw(
            endpoint: "covers", query: "fields image_id; where game = \(igdbID); limit 50;")
        async let artworkRows = IGDBService.raw(
            endpoint: "artworks", query: "fields image_id; where game = \(igdbID); limit 50;")
        covers = (await coverRows).compactMap { $0["image_id"] as? String }
        artworks = (await artworkRows).compactMap { $0["image_id"] as? String }
    }
}
