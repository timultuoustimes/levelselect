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
struct RemoteImageViewer: View {
    let url: URL?
    @Environment(\.dismiss) private var dismiss

    /// Pinch to zoom, and a double-tap for people who do not think to pinch.
    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        NavigationStack {
            Group {
                if let url {
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
                } else {
                    ContentUnavailableView("No image", systemImage: "photo")
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

/// `URL` is not `Identifiable`, and `.sheet(item:)` needs something that is.
struct ZoomTarget: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
    init(_ url: URL) { self.url = url }
}
