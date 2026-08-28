import SwiftUI
import SwiftData

/// What the pictures you've added are costing, and where they are.
///
/// Images are the first thing in this app with a size worth knowing about:
/// they sync to every device and ride along in every export. Somewhere has to
/// answer "how much is this?" before someone finds out from an export that
/// won't open or an iCloud account that's full.
///
/// Deliberately read-mostly. Removing a picture belongs beside the picture —
/// on the game page, where you can see which one you're removing — not in a
/// settings list of anonymous thumbnails.
struct ImageStorageView: View {
    @Environment(\.modelContext) private var context

    @Query(filter: #Predicate<GameImage> { $0.deletedAt == nil },
           sort: \GameImage.addedAt, order: .reverse)
    private var images: [GameImage]

    private var totalBytes: Int { images.reduce(0) { $0 + $1.byteCount } }

    var body: some View {
        List {
            Section {
                LabeledContent("Pictures", value: "\(images.count)")
                LabeledContent("Space used", value: ImageIngest.formattedBytes(totalBytes))
            } footer: {
                Text("Pictures you add are shrunk before they're saved, so they stay small enough to sync and to travel in your export. They live on your device and in your own iCloud, exactly like the rest of your library — nothing is uploaded anywhere else.")
            }

            if images.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No pictures yet",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("Add one from a game's Media section, or when choosing its cover, logo or backdrop."))
                }
            } else {
                Section {
                    ForEach(byGame, id: \.name) { row in
                        LabeledContent(row.name) {
                            Text("\(row.count) · \(ImageIngest.formattedBytes(row.bytes))")
                                .foregroundStyle(.secondary)
                                .font(.callout.monospacedDigit())
                        }
                    }
                } header: {
                    Text("Games with pictures")
                } footer: {
                    Text("Remove a picture from the game it belongs to — its Media section, or the artwork picker.")
                }
            }
        }
        .navigationTitle("Game images")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    /// Grouped by game, heaviest first — the useful order when the question
    /// is "what's taking up the space".
    private var byGame: [(name: String, count: Int, bytes: Int)] {
        var tally: [String: (count: Int, bytes: Int)] = [:]
        for image in images {
            let name = image.game?.name ?? "Removed game"
            var entry = tally[name] ?? (0, 0)
            entry.count += 1
            entry.bytes += image.byteCount
            tally[name] = entry
        }
        return tally
            .map { (name: $0.key, count: $0.value.count, bytes: $0.value.bytes) }
            .sorted { ($0.bytes, $1.name) > ($1.bytes, $0.name) }
    }
}
