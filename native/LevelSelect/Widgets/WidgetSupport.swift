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
    var track: Color = Color.white.opacity(0.14)

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
