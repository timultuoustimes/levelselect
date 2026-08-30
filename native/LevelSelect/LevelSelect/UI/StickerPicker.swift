#if os(iOS)
import SwiftUI
import UIKit

/// Pick a sticker as a profile picture — Memoji, Genmoji, or any other.
///
/// There is no Memoji *library* API — Memoji aren't files and aren't in
/// Photos. The one supported route is `NSAdaptiveImageGlyph`: a text view that
/// opts in receives stickers from the emoji keyboard's drawer, each carrying
/// its own image data.
///
/// Which turned out to be worth more than the feature asked for. That drawer
/// is not only Memoji: it serves Genmoji, Live Stickers someone cut out of
/// their own photos, and sticker packs from other apps. Anything that inserts
/// as an adaptive image glyph arrives here, so a request for "Memoji" bought
/// every sticker on the device.
///
/// So this is a text field nobody types into. It exists to receive one
/// sticker, take the image out of it, and close.
struct StickerPicker: View {
    var onPick: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // The catcher fills the screen behind the instructions, which are
        // themselves not tappable. So a tap ANYWHERE focuses the field and
        // brings the keyboard back — otherwise, losing focus once left a
        // screen telling you to tap a keyboard that was no longer there, with
        // no way to summon it.
        ZStack {
            MemojiCatcher { data in
                onPick(data)
                dismiss()
            }
            .opacity(0.02)

            VStack(spacing: 10) {
                Image(systemName: "face.smiling")
                    .font(.system(size: 44))
                    .foregroundStyle(LSTheme.accent)
                Text("Choose a sticker")
                    .font(.headline)
                // Says where the control is rather than assuming anyone knows
                // the sticker drawer exists — it is two taps into a keyboard.
                Text("On the keyboard, tap the emoji or globe key, then the sticker drawer. Memoji, Genmoji and your own stickers all work. Pick one and it becomes your picture straight away.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                Text("Tap anywhere to bring the keyboard back.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
            .padding(.bottom, 120)
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Stickers")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }
}

/// A `UITextView` whose only job is to receive one Memoji sticker.
private struct MemojiCatcher: UIViewRepresentable {
    var onCatch: (Data) -> Void

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        // The opt-in. Without it the sticker drawer inserts nothing here.
        view.supportsAdaptiveImageGlyph = true
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.isScrollEnabled = false
        DispatchQueue.main.async { view.becomeFirstResponder() }
        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCatch: onCatch) }

    final class Coordinator: NSObject, UITextViewDelegate {
        let onCatch: (Data) -> Void
        init(onCatch: @escaping (Data) -> Void) { self.onCatch = onCatch }

        func textViewDidChange(_ textView: UITextView) {
            let text = textView.attributedText
            let full = NSRange(location: 0, length: text?.length ?? 0)
            var found: Data?
            text?.enumerateAttribute(.adaptiveImageGlyph, in: full) { value, _, stop in
                if let glyph = value as? NSAdaptiveImageGlyph {
                    found = glyph.imageContent
                    stop.pointee = true
                }
            }
            guard let found else { return }
            // Clear it, so a second sticker isn't read as the first again.
            textView.attributedText = NSAttributedString(string: "")
            onCatch(found)
        }
    }
}
#endif
