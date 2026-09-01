import SwiftUI

// Moved out of ThemePalette on 2026-09-01. The widget extension needs it too,
// now that the snapshot carries the user's accent -- and Shared is compiled
// into both targets, so this has to live here rather than be copied.

// MARK: - Color ↔ hex

extension Color {
    init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let rgb = UInt64(value, radix: 16) else { return nil }
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }

    func hexString() -> String? {
        #if os(macOS)
        guard let converted = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let r = converted.redComponent, g = converted.greenComponent, b = converted.blueComponent
        #else
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        #endif
        return String(format: "#%02X%02X%02X",
                      Int(round(r * 255)), Int(round(g * 255)), Int(round(b * 255)))
    }
}
