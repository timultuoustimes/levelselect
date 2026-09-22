import SwiftUI

/// **The console's logo where its name was**, at the top of its page.
///
/// Same rules as a game page's wordmark: `Use game logos` in Settings turns
/// it off, the largest text sizes get the name back (a logo is a picture of
/// text and can't grow with it), and until the logo arrives — or when there
/// isn't one — the name is drawn as it always was. The name stays the
/// accessibility label either way.
struct ConsoleLogoTitle: View {
    /// The canonical platform.
    let platform: String
    /// The largest the logo may be. It fits inside, keeping its shape.
    var maxWidth: CGFloat = 190
    var maxHeight: CGFloat = 30
    /// Drawn when there's no logo.
    var font: Font = .headline

    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var prepared: ConsoleLogoArt.Prepared?

    private var short: String { PlatformShort.builtinName(platform) }
    private var shown: String { PlatformShort.name(platform) }

    private var entry: ConsoleLogo.Entry? {
        guard ThemePalette.showGameLogos, !typeSize.isAccessibilitySize else { return nil }
        return ConsoleLogo.entry(console: short, shown: shown)
    }

    var body: some View {
        Group {
            if let entry, let art = prepared ?? ConsoleLogoArt.cached(entry) {
                Image(decorative: scheme == .dark ? art.dark : art.light, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxWidth: maxWidth, maxHeight: maxHeight)
                    .accessibilityElement()
                    .accessibilityLabel(shown)
                    .accessibilityAddTraits(.isHeader)
            } else {
                Text(shown).font(font)
            }
        }
        .task(id: entry?.file) {
            prepared = nil
            guard let entry else { return }
            prepared = await ConsoleLogoArt.load(entry)
        }
    }
}
