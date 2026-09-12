import SwiftUI
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Choose which part of an image becomes the avatar.
///
/// Game artwork is wide — a 16:9 painting of a whole scene — and an avatar is
/// square. Something has to decide which part survives, and the honest answer
/// is the person, not a center-crop: the character is rarely in the middle.
///
/// Only ever shown for images WITHOUT transparency. A cut-out PNG already is
/// the subject with nothing around it, so cropping one would be asking a
/// question that has no answer.
struct AvatarCropView: View {
    let source: Data
    var onCrop: (Data) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat = 1
    @State private var committedScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero
    @State private var failed = false

    /// The side of the square viewport, in points.
    private let viewport: CGFloat = 280

    private var cgImage: CGImage? {
        guard let src = CGImageSourceCreateWithData(source as CFData, nil),
              CGImageSourceGetCount(src) > 0 else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let cgImage {
                    Image(decorative: cgImage, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .scaleEffect(scale)
                        .offset(offset)
                        .frame(width: viewport, height: viewport)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18)
                                .strokeBorder(.white.opacity(0.35), lineWidth: 1)
                        }
                        .gesture(
                            SimultaneousGesture(
                                DragGesture()
                                    .onChanged { value in
                                        offset = CGSize(
                                            width: committedOffset.width + value.translation.width,
                                            height: committedOffset.height + value.translation.height)
                                    }
                                    .onEnded { _ in committedOffset = offset },
                                MagnifyGesture()
                                    .onChanged { value in
                                        scale = max(1, committedScale * value.magnification)
                                    }
                                    .onEnded { _ in committedScale = scale }
                            )
                        )

                    // A slider as well as pinch: pinching a 280pt square to a
                    // precise framing is fiddly, and on the Mac there is no
                    // pinch at all.
                    HStack(spacing: 10) {
                        Image(systemName: "minus.magnifyingglass").foregroundStyle(.secondary)
                        Slider(value: $scale, in: 1...4) { editing in
                            if !editing { committedScale = scale }
                        }
                        Image(systemName: "plus.magnifyingglass").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: viewport)

                    Text("Drag to move, pinch or slide to zoom.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ContentUnavailableView("That image can't be read",
                                           systemImage: "exclamationmark.triangle")
                }

                if failed {
                    Text("That crop couldn't be saved. Try a different area.")
                        .font(.footnote)
                        .foregroundStyle(LSTheme.working)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Position")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use") { commit() }.disabled(cgImage == nil)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 560)
        #endif
    }

    /// Turn the on-screen position into a pixel rectangle and cut it out.
    ///
    /// `.fill` matches the image's SHORTER edge to the viewport, so that edge
    /// sets the base scale and everything else follows from it.
    private func commit() {
        guard let cgImage else { return }
        let w = CGFloat(cgImage.width), h = CGFloat(cgImage.height)
        let base = viewport / min(w, h)
        let effective = base * scale

        let side = viewport / effective
        // A positive drag moves the image right, revealing what lies to its
        // LEFT — hence the subtraction.
        let centerX = w / 2 - offset.width / effective
        let centerY = h / 2 - offset.height / effective

        var rect = CGRect(x: centerX - side / 2, y: centerY - side / 2, width: side, height: side)
        rect.size.width = min(rect.width, w)
        rect.size.height = min(rect.height, h)
        // Panning is unconstrained while dragging so it never feels sticky;
        // the correction happens once, here.
        rect.origin.x = min(max(0, rect.origin.x), w - rect.width)
        rect.origin.y = min(max(0, rect.origin.y), h - rect.height)

        guard let cut = cgImage.cropping(to: rect.integral),
              let data = Self.encode(cut) else { failed = true; return }
        // The editor closes the sheet; see AvatarArtworkPicker.
        onCrop(data)
    }

    /// PNG, so a cropped region of a transparent source keeps its alpha.
    /// `ImageIngest.prepareAvatar` decides the final encoding and size.
    private static func encode(_ image: CGImage) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}
