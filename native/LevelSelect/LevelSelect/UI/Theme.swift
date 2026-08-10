import SwiftUI

/// LevelSelect visual identity: purple primary + dark gradient surfaces,
/// matching the web app's look (Tim: "purple as the main color, and I like
/// the gradients").
enum LSTheme {
    static let purple = Color(red: 0.58, green: 0.36, blue: 0.98)   // primary accent
    static let purpleDeep = Color(red: 0.30, green: 0.16, blue: 0.55)

    /// App background: near-black with a purple cast at the top.
    static var background: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.10, green: 0.07, blue: 0.18),
                Color(red: 0.05, green: 0.04, blue: 0.09),
            ],
            startPoint: .top, endPoint: .bottom
        )
    }

    /// Hero card gradient (Continue Playing).
    static var heroGradient: LinearGradient {
        LinearGradient(
            colors: [purpleDeep.opacity(0.85), Color(red: 0.12, green: 0.08, blue: 0.22)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    /// Subtle card surface on the dark background.
    static var cardFill: Color { .white.opacity(0.06) }
}

extension View {
    /// Full-bleed themed background.
    func lsBackground() -> some View {
        background(LSTheme.background.ignoresSafeArea())
    }

    /// Card surface used across Stats/Home.
    func lsCard() -> some View {
        padding(14)
            .background(LSTheme.cardFill, in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.07), lineWidth: 1))
    }
}

/// Springy pressed state for tappable cards ("fluid buttons" — everything
/// moves, nothing snaps). Honors Reduce Motion by keeping the scale subtle.
struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
