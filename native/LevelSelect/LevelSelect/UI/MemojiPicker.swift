#if os(iOS)
import SwiftUI
import UIKit

/// Pick a Memoji as a profile picture.
///
/// There is no Memoji *library* API — Memoji aren't files and aren't in
/// Photos. The one supported route is `NSAdaptiveImageGlyph`: a text view that
/// opts in gets Memoji stickers from the emoji keyboard's sticker drawer, and
/// each one carries its own image data.
///
/// So this is a text field the user never types into. It exists to receive one
/// sticker, take the image out of it, and close. The keyboard opens straight
/// onto the sticker drawer.
struct MemojiPicker: View {
    var onPick: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            MemojiCatcher { data in
                onPick(data)
                dismiss()
            }
            .frame(height: 1)
            .opacity(0.01)

            VStack(spacing: 8) {
                Image(systemName: "face.smiling")
                    .font(.system(size: 44))
                    .foregroundStyle(LSTheme.accent)
                Text("Choose a Memoji")
                    .font(.headline)
                // Says where the control is rather than assuming anyone knows
                // the sticker drawer exists — it is two taps into a keyboard.
                Text("Tap the emoji or globe key on the keyboard, open the sticker drawer, then pick a Memoji. It becomes your picture straight away.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            Spacer()
        }
        .padding(.top, 28)
        .navigationTitle("Memoji")
        .navigationBarTitleDisplayMode(.inline)
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
