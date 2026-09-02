import SwiftUI

/// Load a cached cover (by file name) from the App Group as a SwiftUI Image.
func loadCover(_ fileName: String?) -> Image? {
    guard let url = WidgetShared.coverURL(fileName),
          let data = try? Data(contentsOf: url),
          let ui = UIImage(data: data) else { return nil }
    return Image(uiImage: ui)
}

/// Compact playtime, e.g. "2h 14m", "12m", "8s".
func lsPlaytime(_ seconds: Double) -> String {
    let s = max(0, Int(seconds))
    let h = s / 3600, m = (s % 3600) / 60
    if h > 0 { return "\(h)h \(m)m" }
    if m > 0 { return "\(m)m" }
    return "\(s)s"
}

/// Hours label for stat tiles, e.g. "3.5h" or "0h".
func lsHours(_ seconds: Double) -> String {
    let hours = seconds / 3600
    if hours >= 10 { return "\(Int(hours.rounded()))h" }
    return String(format: "%.1fh", hours)
}

/// A progress ring (used by the completion + run widgets).
struct RingView: View {
    let progress: Double        // 0…1
    var lineWidth: CGFloat = 8
    var tint: Color = LSWidget.torch
    /// The unfilled part of the ring — a surface, so it follows the theme.
    var track: Color = LSTheme.cardFill

    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: The widget's ground

extension LSWidget {
    /// What the app is set to, read from the snapshot.
    ///
    /// A widget cannot use `.preferredColorScheme` — WidgetKit hands it the
    /// system's scheme and ignores that modifier — so the choice arrives as an
    /// environment override on the content instead. Without it, an app pinned
    /// to Light would sit beside dark widgets on the same Home Screen.
    static var appearance: LSAppearance {
        LSAppearance(raw: WidgetSnapshot.load()?.appearanceRaw)
    }

    /// The same ground the app draws, from the same function — so a widget
    /// beside the app is the same colour rather than a good match.
    static var ground: LinearGradient {
        LSTheme.ground(tintedBy: WidgetSnapshot.load()?.backgroundHex.flatMap { Color(hex: $0) })
    }
}

extension View {
    /// One place every widget gets its ground and its theme.
    ///
    /// Fifteen widgets each repeated the same navy gradient literal, which is
    /// why they all stayed dark when the app learned to be light — there was
    /// no single thing to change. Now there is.
    func lsWidgetSurface() -> some View {
        modifier(LSWidgetSurface())
    }
}

private struct LSWidgetSurface: ViewModifier {
    func body(content: Content) -> some View {
        // **The scheme has to be the OUTERMOST modifier**, wrapping the
        // background as well as the content.
        //
        // The first version put it on `content` and attached
        // `containerBackground` outside that — so the text resolved against
        // the override while the ground resolved against the system, and a
        // Light app on a Dark phone drew black labels on a dark ground.
        // Ground and text are one decision; splitting them across an
        // environment boundary is what made them disagree.
        //
        // `.system` still applies nothing, so the widget keeps following the
        // phone rather than being pinned to a copy of whatever the snapshot
        // was written with.
        Group {
            if let scheme = LSWidget.appearance.colorScheme {
                content
                    .containerBackground(for: .widget) { LSWidget.ground }
                    .environment(\.colorScheme, scheme)
            } else {
                content
                    .containerBackground(for: .widget) { LSWidget.ground }
            }
        }
    }
}
