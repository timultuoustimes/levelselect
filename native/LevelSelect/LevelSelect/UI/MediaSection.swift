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
    @State private var videoIDs: [String] = []
    @State private var playingTrailer: String?
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
                                    shot(id, size: "t_screenshot_big")
                                        .frame(width: 248, height: 140)
                                        .clipShape(.rect(cornerRadius: 10))
                                        .overlay(RoundedRectangle(cornerRadius: 10)
                                            .strokeBorder(.white.opacity(0.08), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Screenshot")
                                .accessibilityHint("Opens full size")
                            }
                        }
                    }

                    // Trailers, the same ones the add screen shows. The game
                    // page had every other kind of media IGDB publishes and
                    // not this one, so the only way to watch a trailer for a
                    // game you already own was to leave the app.
                    if let playing = playingTrailer {
                        ZStack(alignment: .topTrailing) {
                            TrailerPlayer(youtubeID: playing)
                                .aspectRatio(16 / 9, contentMode: .fit)
                                .background(.black)
                            Button { playingTrailer = nil } label: {
                                Image(systemName: "xmark")
                                    .font(.caption.weight(.bold))
                                    .padding(7)
                                    .background(.black.opacity(0.55), in: .circle)
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                            .padding(8)
                        }
                    }
                    if !videoIDs.isEmpty {
                        Text("Trailers")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(videoIDs, id: \.self) { id in
                                    Button {
                                        playingTrailer = id
                                    } label: {
                                        AsyncImage(url: URL(string:
                                            "https://img.youtube.com/vi/\(id)/hqdefault.jpg")) { image in
                                            image.resizable().aspectRatio(contentMode: .fill)
                                        } placeholder: {
                                            RoundedRectangle(cornerRadius: 10).fill(.quaternary)
                                        }
                                        .frame(width: 248, height: 140)
                                        .clipShape(.rect(cornerRadius: 10))
                                        .overlay {
                                            Image(systemName: "play.circle.fill")
                                                .font(.system(size: 38))
                                                .foregroundStyle(.white.opacity(0.92))
                                                .shadow(radius: 6)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Trailer")
                                }
                            }
                        }
                    }
                }
            }
        }
        .task { await load() }
        .task(id: photoItem) { await ingestPickedPhoto() }
        .sheet(item: $viewing) { item in
            // One viewer for the app: the add screen needed the same thing,
            // and two of these drift until one loses the pinch gesture.
            RemoteImageViewer(url: URL(string:
                "https://images.igdb.com/igdb/image/upload/t_1080p/\(item.imageID).jpg"))
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
        // Videos first, and outside the screenshot cache's early return —
        // that cache only ever held image ids, so returning from it skipped
        // the trailers entirely on every visit after the first.
        // From the game record, not a `game_videos` lookup — that endpoint
        // came back empty through the proxy, and the main query already
        // carries `videos.video_id` for every screen that needs it.
        videoIDs = (try? await IGDBService.lookup(id: igdbID))??.videoIDs ?? []
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
///
/// Not private: the journal shows the same pictures and needs the same
/// viewer. Two of these would drift until one lost the caption field.
struct LocalImageViewer: View {
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

