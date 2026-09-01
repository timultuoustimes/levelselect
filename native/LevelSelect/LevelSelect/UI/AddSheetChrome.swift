import SwiftUI

/// The surface a row on the add screen sits on.
///
/// `.ultraThinMaterial` alone was flat: a single grey tone with nothing
/// happening across it, which is what Tim was reacting to — *"I think the
/// cards should be a little more interesting than the flat grey as well."*
///
/// Three cheap layers instead. The material still does the frosting, a faint
/// top-to-bottom lift gives the card a light source, and a hairline that is
/// brighter at the top than the bottom is what reads as an edge catching that
/// light. Static, so it costs nothing to put under every row.
struct AddSheetCard: View {
    var cornerRadius: CGFloat = 14

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(LinearGradient(
                        colors: [.white.opacity(0.07), .white.opacity(0.015)],
                        startPoint: .top, endPoint: .bottom))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(LinearGradient(
                        colors: [.white.opacity(0.16), .white.opacity(0.04)],
                        startPoint: .top, endPoint: .bottom), lineWidth: 1)
            }
            .padding(.vertical, 2)
    }
}

/// A web page, inside the app.
///
/// Tim: *"Can you let users view the igdb and deku deals page right in the
/// picker?"* Being sent to Safari to check a price loses the search you just
/// did and the game you were halfway through deciding on.
///
/// Wraps the pane the Deku browser already uses, so there is one web view in
/// the app rather than a second one that will drift.
struct InAppBrowser: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var current: URL

    init(url: URL) {
        self.url = url
        _current = State(initialValue: url)
    }

    var body: some View {
        DekuBrowserPane(url: $current, onSyncRequest: {})
            .lsBackground()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
    }
}
