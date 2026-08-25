import SwiftUI

/// The first thing a stranger sees, once, before the empty state.
///
/// One screen, no pager — the app deliberately has no tour, and this is not
/// one. It exists for a single sentence the empty state can't carry: the
/// privacy stance, said in the app's own voice before anything else happens.
/// Strangers arrive here from an invite form that promised "no accounts";
/// the first screen should keep that promise out loud, in the spot every
/// other app uses for "Sign in with…".
///
/// Both buttons hand off to the same actions the empty state offers, in the
/// same order and nearly the same words, so the welcome flows into the app
/// rather than competing with it. Swiping the sheet away counts as seeing it
/// — it never comes back.
struct WelcomeView: View {
    /// What the person chose on the way out; the presenter opens the matching
    /// sheet after this one is gone (presenting from onDismiss avoids the
    /// sheet-over-sheet race).
    enum Choice { case addGame, importCSV }
    var onChoice: (Choice) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 28)

            Image("DoorMark")
                .resizable()
                .scaledToFit()
                .frame(height: 64)
                .shadow(color: .black.opacity(0.5), radius: 8, y: 3)
                .padding(.bottom, 14)

            Wordmark(size: 19)

            Text("Every game you're playing,\nand exactly where you left off.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 10)

            VStack(alignment: .leading, spacing: 18) {
                row("gamecontroller", "A shelf, not a spreadsheet",
                    "Add the games you're actually playing.")
                row("clock", "Sessions time themselves",
                    "Start from the app, a widget, your watch, or the Lock Screen.")
                // Real lists first, generation last — pasting beats
                // generating, and the welcome shouldn't imply otherwise.
                row("checklist", "The game's real checklist",
                    "Import real achievements, paste a guide you trust, or plan it a piece at a time.")
                row("lock", "Yours, privately",
                    "Your device and your own iCloud. No account, no ads, no tracking.")
            }
            .padding(.horizontal, 6)
            .padding(.top, 26)

            Spacer(minLength: 24)

            VStack(spacing: 4) {
                Button {
                    finish(.addGame)
                } label: {
                    Text("Start Your Shelf")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)

                Button("Import a Spreadsheet") {
                    finish(.importCSV)
                }
                .buttonStyle(.borderless)
                .padding(.top, 6)

                Text("There's nothing to sign up for.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 10)
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 22)
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .lsBackground()
    }

    private func finish(_ choice: Choice) {
        onChoice(choice)
        dismiss()
    }

    private func row(_ symbol: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(LSTheme.accent)
                .frame(width: 34, height: 34)
                .background(LSTheme.accent.opacity(0.13),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(body)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
