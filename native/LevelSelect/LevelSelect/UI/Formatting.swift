import SwiftUI

enum Format {
    /// Compact human duration, e.g. "1h 12m", "12m 5s", "42s".
    static func duration(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(sec)s" }
        return "\(sec)s"
    }

    /// Video timestamp, e.g. "4:02" or "1:12:41".
    static func timestamp(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec)
                     : String(format: "%d:%02d", m, sec)
    }

    /// Stopwatch clock, e.g. "01:02:03".
    static func clock(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }
}

extension GameStatus {
    var label: String { rawValue.capitalized }

    /// Themed status color (user override → default palette).
    @MainActor
    var color: Color {
        ThemePalette.color(for: self)
    }

    var systemImage: String {
        switch self {
        case .playing:   "play.circle.fill"
        case .paused:    "pause.circle.fill"
        case .completed: "checkmark.circle.fill"
        case .queued:    "text.append"
        case .backlog:   "tray.full"
        case .shelved:   "archivebox"
        case .abandoned: "xmark.circle"
        case .wishlist:  "heart.fill"
        }
    }

    /// Display order for grouped library sections.
    static var displayOrder: [GameStatus] {
        [.playing, .paused, .queued, .backlog, .wishlist, .completed, .shelved, .abandoned]
    }

    var sectionTitle: String {
        switch self {
        case .playing:   "Now Playing"
        case .paused:    "Paused"
        case .queued:    "Up Next"
        case .backlog:   "Backlog"
        case .completed: "Completed"
        case .shelved:   "Shelved"
        case .abandoned: "Abandoned"
        case .wishlist:  "Wishlist"
        }
    }
}

/// Tim's platform preference for defaulting new adds: Nintendo eShop first
/// (Switch 2, then Switch), then Steam/PC, then Mac; everything else after,
/// in IGDB's order.
enum PlatformPreference {
    static func rank(_ platform: String) -> Int {
        let p = platform.lowercased()
        if p.contains("switch 2") { return 0 }
        if p.contains("switch") { return 1 }
        if p.contains("windows") || p == "pc" || p.contains("steam") { return 2 }
        if p.contains("mac") { return 3 }
        return 100
    }

    /// Stable sort: preferred platforms first, original order preserved otherwise.
    static func sorted(_ platforms: [String]) -> [String] {
        platforms.enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
    }
}

/// Async cover art with a themed placeholder. Box-art aspect ratio.
struct CoverThumb: View {
    let urlString: String?
    var body: some View {
        Group {
            if let s = urlString, let url = URL(string: s) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    case .empty: ProgressView()
                    default: placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .clipShape(.rect(cornerRadius: 6))
        .coverGloss(cornerRadius: 6)
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator, lineWidth: 0.5))
    }

    private var placeholder: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            Image(systemName: "gamecontroller.fill").foregroundStyle(.secondary)
        }
    }
}
