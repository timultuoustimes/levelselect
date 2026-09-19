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
                // **The app icon itself, in the app icon's shape.**
                //
                // `DoorMark` used to be the door art cut out along a ragged
                // hand-drawn silhouette — notched corners, a wobbly outline —
                // and the rounded clip over it did nothing, because the art
                // never reached the corners to be clipped. What you saw was
                // the ragged edge. Tim: *"it looks terrible currently with the
                // weird cutout... we just need to use the app icon shape."*
                //
                // So `DoorMark` is now the icon tile, square and full-bleed,
                // and the clip is the real thing: a square frame at iOS's own
                // corner ratio, which is what makes it read as the app's icon
                // rather than a picture of a door.
                Image("DoorMark")
                    .resizable()
                    .frame(width: iconSide, height: iconSide)
                    .clipShape(.rect(cornerRadius: iconSide * Self.iconCornerRatio,
                                     style: .continuous))
                    .shadow(color: .black.opacity(0.5), radius: size * 0.35, y: size * 0.12)
            }
            Text("LevelSelect")
                .font(LSTheme.pixel(size))
            .fontDesign(nil)   // never let an app-wide design override the pixel face
                .foregroundStyle(tint)
                .shadow(color: shadowTint, radius: 0, y: shadowOffset)
                .shadow(color: tint.opacity(0.3), radius: size * 0.65)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("LevelSelect")
        .accessibilityAddTraits(.isHeader)
    }

    /// iOS's own icon corner ratio — the squircle is ~22.37% of the side.
    private static let iconCornerRatio = 0.2237

    private var iconSide: CGFloat { (size * 2.1).rounded() }

    /// One block of the face — see `LSTheme.pixelStep(for:)`, which is where
    /// the 8×8 grid and the floor-don't-round rule are derived.
    ///
    /// This was `size * 0.16` (3.52pt at the Settings size, well over a block,
    /// which is the smeared detached bar Tim reported), then briefly
    /// `(size / 8).rounded()`, which at that same size gives 3 — a quarter of
    /// a block too far, and the exact value `ProfileHeader` had already found
    /// leaves a lit gap.
    private var shadowOffset: CGFloat { LSTheme.pixelStep(for: size) }

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


extension View {
    /// The wordmark, pinned to the leading edge of the navigation bar.
    ///
    /// **Home only.** It was on all four tabs for a day. Fable argued against
    /// that before it shipped — *"The wordmark on Home says 'this is the app';
    /// on Library it would say 'this is a brand'"* — Tim asked for it anyway,
    /// looked at it, and agreed: *"it feels weird to have the app name on every
    /// tab, just like Fable said it would. I think it was the wrong call."*
    ///
    /// It cost more than a word, too. On a tab with a large title the mark sits
    /// in its own band above that title, so Library spent a row of the screen
    /// saying something the reader already knew. Removing it lets the system do
    /// what it does everywhere else and the gap closes — which is what Tim
    /// asked for, pointing at Gamery.
    ///
    /// Home keeps it because Home has no large title and its art bleeds to the
    /// top edge, so the mark sits ON the artwork rather than in a band of its
    /// own — no row spent, and it is the one screen where naming the app is
    /// the point.
    ///
    /// Hidden from VoiceOver: the navigation title already names where you are.
    func lsWordmarkHeader() -> some View {
        #if os(macOS)
        return self
        #else
        return toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Wordmark(size: 13)
                    .lineLimit(1)
                    .fixedSize()
                    .accessibilityHidden(true)
            }
            // **No glass capsule.** iOS 26 gives every toolbar item its own
            // glass background; `.principal` items are exempt, which is why the
            // wordmark had none while it sat centered on Home and grew one the
            // moment it moved to the leading edge. It is a wordmark, not a
            // control — a capsule around it says "tap me" about the one thing
            // in the bar that does nothing.
            .sharedBackgroundVisibility(.hidden)
        }
        #endif
    }
}
