import SwiftUI

/// The invite form's two questions, offered in-app — once.
///
/// The public TestFlight link made the funnel form-optional: strangers can
/// install without ever seeing "what do you play, and how do you track it
/// today?", which is the feedback that actually steers the roadmap. This
/// card closes that gap without breaking the privacy stance: the app itself
/// still collects nothing — the button opens the same web form the invite
/// flow uses, answering is a choice, and any dismissal is permanent.
struct BetaQuestionCard: View {
    /// Once per device. Not synced: it's a prompt, not data.
    @AppStorage("betaQuestionDismissed") private var dismissed = false
    @Environment(\.openURL) private var openURL

    /// TestFlight installs carry a sandbox receipt; App Store ones don't.
    /// Debug builds show the card so it can be seen and styled in development.
    private static var isBetaInstall: Bool {
        #if DEBUG
        true
        #else
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }

    var body: some View {
        if !dismissed && Self.isBetaInstall {
            VStack(alignment: .leading, spacing: 10) {
                Label("One question from the developer", systemImage: "hand.wave")
                    .font(.subheadline.weight(.semibold))
                Text("What do you play, and how do you track it today? Two questions on the web — they genuinely shape what gets built next. The app itself collects nothing, so this is the only way I'd ever know.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Answer on the web") {
                        if let url = URL(string: "https://levelselect.app/invite/?tester=1") {
                            openURL(url)
                        }
                        dismissed = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    Button("No thanks") { dismissed = true }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LSTheme.accent.opacity(0.10), in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(LSTheme.accent.opacity(0.25), lineWidth: 1)
            }
            .padding(.horizontal)
        }
    }
}
