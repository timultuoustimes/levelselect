import SwiftUI

/// IGDB screenshots for the game page's Media section. Display-only — the
/// screenshots endpoint was already on the proxy's allowlist, so this costs
/// no backend change. User-added images are a different feature with a real
/// schema/export/deletion story; deliberately not started here.
struct ScreenshotStrip: View {
    let game: Game

    @State private var imageIDs: [String] = []
    @State private var loaded = false
    @State private var viewing: ScreenshotItem?

    /// Session cache so revisiting a page doesn't re-spend proxy quota.
    @MainActor private static var cache: [Int: [String]] = [:]

    var body: some View {
        Group {
            if !loaded {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            } else if imageIDs.isEmpty {
                Text("No screenshots on IGDB for this game.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(imageIDs, id: \.self) { id in
                            Button {
                                viewing = ScreenshotItem(imageID: id)
                            } label: {
                                shot(id, size: "t_screenshot_med")
                                    .frame(width: 200, height: 112)
                                    .clipShape(.rect(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Screenshot")
                            .accessibilityHint("Opens full size")
                        }
                    }
                }
            }
        }
        .task { await load() }
        .sheet(item: $viewing) { item in
            ScreenshotViewer(imageID: item.imageID)
        }
    }

    private func shot(_ id: String, size: String) -> some View {
        AsyncImage(url: URL(string: "https://images.igdb.com/igdb/image/upload/\(size)/\(id).jpg")) { phase in
            if case .success(let image) = phase {
                image.resizable().scaledToFill()
            } else {
                Rectangle().fill(.quaternary)
            }
        }
    }

    private func load() async {
        guard !loaded else { return }
        defer { loaded = true }
        guard let igdbID = game.igdbID else { return }
        if let hit = Self.cache[igdbID] {
            imageIDs = hit
            return
        }
        let rows = await IGDBService.raw(
            endpoint: "screenshots",
            query: "fields image_id; where game = \(igdbID); limit 20;")
        imageIDs = rows.compactMap { $0["image_id"] as? String }
        Self.cache[igdbID] = imageIDs
    }
}

private struct ScreenshotItem: Identifiable {
    let imageID: String
    var id: String { imageID }
}

/// Full-size screenshot, dismissed the way every sheet is.
private struct ScreenshotViewer: View {
    let imageID: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            AsyncImage(url: URL(string: "https://images.igdb.com/igdb/image/upload/t_1080p/\(imageID).jpg")) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFit()
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
