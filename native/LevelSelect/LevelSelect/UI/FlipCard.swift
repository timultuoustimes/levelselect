import SwiftUI

/// A stats card with two faces, and a button that turns it over.
///
/// Tim's design: a small chart-type icon in the card's top-right that swaps
/// bars for a pie, with the card physically turning rather than cross-fading.
/// The turn is the point — it says the two faces are the SAME data seen
/// differently, where a fade would read as one card replacing another.
///
/// **One face exists at a time**, and the swap happens at the halfway point
/// while the card is edge-on and nothing is visible. The obvious alternative —
/// both faces in a `ZStack`, hiding one — makes the card as tall as the TALLER
/// face always, so a short bar chart floated in a box sized for a pie with the
/// flip button stranded above it. Turning in two halves keeps the card exactly
/// as tall as what it is showing, and hides the substitution inside the
/// animation rather than fighting it.
///
/// The choice is remembered per card and is device-local, like the stats card
/// order beside it: which chart someone prefers on their phone is not
/// something their iPad needs to agree with.
struct FlipCard<Front: View, Back: View>: View {
    let storageKey: String
    @ViewBuilder var front: Front
    @ViewBuilder var back: Back

    @State private var showingBack = false
    @State private var angle: Double = 0
    @State private var turning = false
    @State private var loaded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Half a turn. Short enough not to feel like a transition you have to sit
    /// through when flipping several cards in a row.
    private static var half: Duration { .milliseconds(180) }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if showingBack { back } else { front }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .lsCard()

            Button { flip() } label: {
                Image(systemName: showingBack ? "chart.bar.fill" : "chart.pie.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(LSTheme.accent)
                    .frame(width: 30, height: 30)
                    .glassEffect(.regular, in: .circle)
            }
            .buttonStyle(.plain)
            .padding(10)
            .disabled(turning)
            .accessibilityLabel(showingBack ? "Show as bars" : "Show as a pie chart")
        }
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.35)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            showingBack = UserDefaults.standard.bool(forKey: storageKey)
        }
    }

    private func flip() {
        guard !turning else { return }

        guard !reduceMotion else {
            showingBack.toggle()
            UserDefaults.standard.set(showingBack, forKey: storageKey)
            return
        }

        turning = true
        Task { @MainActor in
            // Out to edge-on, where the card presents no face at all.
            withAnimation(.easeIn(duration: 0.18)) { angle = 90 }
            try? await Task.sleep(for: Self.half)

            // Swap unseen, then come back from the other side so the turn
            // continues in one direction rather than bouncing.
            showingBack.toggle()
            UserDefaults.standard.set(showingBack, forKey: storageKey)
            angle = -90

            withAnimation(.easeOut(duration: 0.18)) { angle = 0 }
            try? await Task.sleep(for: Self.half)
            turning = false
        }
    }
}
