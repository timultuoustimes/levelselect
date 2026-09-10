import SwiftUI

/// One image, as large as the screen allows.
///
/// Art is the reason half of these screens exist, and a 160pt strip of
/// screenshots is a contact sheet rather than a look at the game. Tim, of the
/// add screen: *"can we do bigger artwork and let me tap to view it and
/// screenshots larger."*
///
/// Shared rather than written twice: the Media section already had one of
/// these for the game page, and two viewers drifting apart is how one of them
/// ends up without the pinch gesture or the black ground.
/// **A gallery, not a single picture.**
///
/// It took one URL, so a strip of eight screenshots meant opening and closing
/// eight times to see them. Tim, 2026-09-10: *"I would like to be able to
/// swipe through the other screenshots and not be forced to open and close a
/// screenshot one at a time."*
///
/// The one-URL initializer stays, because two callers open a single cover and
/// a gallery of one is exactly what they should get — the page dots hide
/// themselves at a count of one.
struct RemoteImageViewer: View {
    let urls: [URL]
    @State private var current: URL?
    @Environment(\.dismiss) private var dismiss

    /// One picture — a cover, or anything with no siblings.
    init(url: URL?) {
        urls = url.map { [$0] } ?? []
        _current = State(initialValue: url)
    }

    /// The whole strip, opened at the one that was tapped. A `start` the
    /// strip does not contain — or none at all, when the caller could not
    /// build its URL — opens at the first rather than at nothing.
    init(urls: [URL], start: URL?) {
        self.urls = urls
        _current = State(initialValue: start.flatMap { urls.contains($0) ? $0 : nil } ?? urls.first)
    }

    private var index: Int { current.flatMap { urls.firstIndex(of: $0) } ?? 0 }

    var body: some View {
        NavigationStack {
            Group {
                if urls.isEmpty {
                    ContentUnavailableView("No image", systemImage: "photo")
                } else {
                    #if os(iOS)
                    // TabView's paging IS the swipe. Each page keeps its own
                    // zoom, so returning to one you had zoomed finds it as
                    // you left it.
                    TabView(selection: $current) {
                        ForEach(urls, id: \.self) { url in
                            ZoomableRemoteImage(url: url).tag(Optional(url))
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: urls.count > 1 ? .automatic : .never))
                    .indexViewStyle(.page(backgroundDisplayMode: .interactive))
                    #else
                    // The Mac has no page style and no swipe to speak of, so
                    // it gets the buttons a Mac would expect. Same gallery.
                    ZoomableRemoteImage(url: current ?? urls[0])
                    #endif
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
            .toolbar {
                #if os(macOS)
                if urls.count > 1 {
                    ToolbarItemGroup(placement: .navigation) {
                        Button { step(-1) } label: { Image(systemName: "chevron.left") }
                            .disabled(index == 0)
                            .accessibilityLabel("Previous picture")
                        Button { step(1) } label: { Image(systemName: "chevron.right") }
                            .disabled(index == urls.count - 1)
                            .accessibilityLabel("Next picture")
                    }
                }
                #endif
                // **A `.principal` item, not `navigationTitle`.** The title
                // did not render at all with a paged TabView under it — the
                // bar came up with only Done — so the count went where a
                // toolbar reliably draws.
                if urls.count > 1 {
                    ToolbarItem(placement: .principal) {
                        Text("\(index + 1) of \(urls.count)")
                            .font(.subheadline.weight(.medium).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func step(_ by: Int) {
        let next = index + by
        guard urls.indices.contains(next) else { return }
        current = urls[next]
    }
}

/// One page of the gallery: the picture, pinch to zoom, double-tap for people
/// who do not think to pinch.
private struct ZoomableRemoteImage: View {
    let url: URL
    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        AsyncImage(url: url) { phase in
            if case .success(let image) = phase {
                image.resizable().scaledToFit()
                    .scaleEffect(zoom * pinch)
                    .gesture(
                        MagnifyGesture()
                            .updating($pinch) { value, state, _ in state = value.magnification }
                            .onEnded { value in
                                zoom = min(max(zoom * value.magnification, 1), 6)
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.snappy) { zoom = zoom > 1 ? 1 : 2.5 }
                    }
            } else if case .failure = phase {
                ContentUnavailableView("Couldn't load the image",
                                       systemImage: "photo.badge.exclamationmark")
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// `URL` is not `Identifiable`, and `.sheet(item:)` needs something that is.
struct ZoomTarget: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
    init(_ url: URL) { self.url = url }
}
