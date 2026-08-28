import SwiftUI
import SwiftData
import PhotosUI

/// The game page's Media section: the pictures the user added, then the
/// screenshots IGDB publishes.
///
/// Theirs come first deliberately. A photo someone took of the cartridge they
/// owned is worth more to them than a press screenshot, and a section that
/// opens with stock art reads as a catalogue rather than a notebook.
struct ScreenshotStrip: View {
    let game: Game

    @Environment(\.modelContext) private var context
    @State private var imageIDs: [String] = []
    @State private var loaded = false
    @State private var viewing: ScreenshotItem?
    @State private var viewingLocal: GameImage?
    @State private var photoItem: PhotosPickerItem?
    @State private var importing = false
    @State private var importError: String?

    private var repo: Repository { Repository(context) }

    /// Session cache so revisiting a page doesn't re-spend proxy quota.
    @MainActor private static var cache: [Int: [String]] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let mine = game.liveImages
            if !mine.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(mine) { image in
                            if let data = image.data {
                                Button { viewingLocal = image } label: {
                                    LocalArtworkThumb(data: data)
                                        .frame(width: 200, height: 112)
                                        .clipShape(.rect(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(image.caption ?? "Your image")
                                .accessibilityHint("Opens full size")
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

            HStack {
                PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                    if importing {
                        HStack(spacing: 6) { ProgressView(); Text("Adding…") }
                    } else {
                        Label("Add a picture", systemImage: "photo.badge.plus")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(importing)
                Spacer()
            }

            if let importError {
                Text(importError).font(.caption).foregroundStyle(.red)
            }

            if !loaded {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            } else if imageIDs.isEmpty {
                if mine.isEmpty {
                    Text("No screenshots on IGDB for this game — add your own above.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("From IGDB")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
        }
        .task { await load() }
        .task(id: photoItem) { await ingestPickedPhoto() }
        .sheet(item: $viewing) { item in
            ScreenshotViewer(imageID: item.imageID)
        }
        .sheet(item: $viewingLocal) { image in
            LocalImageViewer(image: image)
        }
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
            try repo.addImage(to: game, data: raw, role: .gallery)
        } catch ImageIngest.Failure.unreadable {
            importError = "That file isn't an image this device can read."
        } catch {
            importError = "Couldn't add that image."
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

/// Full-size view of an image the user added, with its caption editable —
/// the caption is the notebook part ("the cart I traded away").
private struct LocalImageViewer: View {
    @Bindable var image: GameImage
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var caption = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let data = image.data {
                    LocalArtworkThumb(data: data, contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView("Still syncing", systemImage: "icloud.and.arrow.down",
                                           description: Text("This picture hasn't finished downloading to this device."))
                }
                TextField("Caption", text: $caption, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
                    .padding()
            }
            .background(.black)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        let trimmed = caption.trimmingCharacters(in: .whitespaces)
                        if trimmed != (image.caption ?? "") {
                            image.caption = trimmed.isEmpty ? nil : trimmed
                            image.updatedAt = .now
                            image.revision += 1
                            PersistenceMonitor.shared.commit(context)
                        }
                        dismiss()
                    }
                }
            }
            .onAppear { caption = image.caption ?? "" }
        }
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
