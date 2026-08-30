import SwiftUI

/// The LevelSelect wordmark as live type rather than baked artwork.
///
/// Two shadows doing two different jobs:
///  - a **zero-blur offset** for legibility. Press Start 2P strokes are ~2px
///    wide at display sizes, so a blurred shadow eats the corners and the
///    glyphs turn to mush; a hard offset instead adds a second contrast edge
///    and makes the letterforms read *more* sharply. This is the pixel-art
///    convention, and it's why `radius: 0` matters here.
///  - a **soft glow** for the torch-lit atmosphere, which is the only place
///    blur belongs.
///
/// Live text also means it stays crisp at any size (no resampled PNG) and can
/// follow the user's accentColor — see `LSTheme.wordmark`.
struct Wordmark: View {
    var size: CGFloat = 13
    /// Show the door icon to the left of the type.
    var showsIcon = false

    private var tint: Color { LSTheme.wordmark }

    var body: some View {
        HStack(spacing: size * 0.55) {
            if showsIcon {
                // Clipped to a rounded square. The artwork carries its own
                // background out to the edges, so unclipped it read as a
                // square tile pasted onto the card — "a weird cut out" — where
                // rounding makes it read as what it is, an app icon.
                Image("DoorMark")
                    .resizable()
                    .scaledToFit()
                    .frame(height: size * 2.1)
                    .clipShape(.rect(cornerRadius: size * 0.45, style: .continuous))
                    .shadow(color: .black.opacity(0.5), radius: size * 0.35, y: size * 0.12)
            }
            Text("LevelSelect")
                .font(LSTheme.pixel(size))
            .fontDesign(nil)   // never let an app-wide design override the pixel face
                .foregroundStyle(tint)
                .shadow(color: shadowTint, radius: 0, y: max(1, size * 0.16))
                .shadow(color: tint.opacity(0.3), radius: size * 0.65)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("LevelSelect")
        .accessibilityAddTraits(.isHeader)
    }

    /// A darkened version of the tint, so a custom accent gets a shadow that
    /// belongs to it rather than a fixed brown.
    private var shadowTint: Color {
        ThemePalette.accentIsCustom
            ? tint.mix(with: .black, by: 0.55)
            : LSTheme.torchShadow
    }
}

#Preview {
    VStack(spacing: 28) {
        Wordmark(size: 13)
        Wordmark(size: 20, showsIcon: true)
        Wordmark(size: 30)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(LSTheme.background)
}
