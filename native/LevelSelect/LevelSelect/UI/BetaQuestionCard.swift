import SwiftUI

/// One question from the developer, asked in the app — and askable again.
///
/// The public TestFlight link made the invite form optional: strangers can
/// install without ever seeing "what do you play, and how do you track it
/// today?", which is the feedback that actually steers the roadmap. This card
/// closes that gap without breaking the privacy stance: the app itself still
/// collects nothing — the button opens the same web form the invite flow uses,
/// answering is a choice, and a dismissal is respected.
///
/// **Why this is a list rather than a flag.** It used to be one boolean,
/// `betaQuestionDismissed`, set forever the first time anyone tapped "No
/// thanks". That meant every tester who declined during build 31 was
/// unreachable for every build after it — five builds of questions attached to
/// TestFlight release notes, read at install time when nobody has an opinion
/// yet, and no way for the app to ask anything later. The questions were not
/// being ignored; there was no channel left to ask them on.
///
/// So questions are an ordered list and the card shows **the first one this
/// device has not answered**. Two consequences, both wanted:
///
/// - A stranger arriving cold gets the onboarding question first, because it
///   is the only one they can answer on day one.
/// - Someone who has been here since 31 has already dealt with that one, so
///   they get the current build's question instead.
///
/// Each build appends one question. Nobody is asked twice.
struct BetaQuestionCard: View {
    struct Question: Identifiable {
        let id: String
        let prompt: String
    }

    /// Oldest first — the card shows the first unanswered one, so order is
    /// the sequence a new tester walks through, not a priority list.
    static let questions: [Question] = [
        Question(
            id: "before",
            // The question that names something to be compared against.
            // Everything else is nice to know.
            prompt: """
            What were you using to keep track before this? A spreadsheet, \
            another app, nothing at all — whichever it is, it's the most useful \
            thing you can tell me, because it's what LevelSelect is being \
            measured against.
            """),
        Question(
            id: "journal-36",
            prompt: """
            Have you written anything down yet? The Journal tab is new — a note \
            on a session, or a memory from years before you had the app. \
            Whether you used it or ignored it completely, that's the thing I \
            most need to know about this build.
            """),
    ]

    /// Ids already answered or declined, comma-separated. Not synced: it's a
    /// record of what this device has been shown, not data about the person.
    @AppStorage("betaQuestionsAnswered") private var answeredRaw = ""
    /// The old single flag, read once so someone who declined the first
    /// question is not asked it again — but is still reachable for later ones.
    @AppStorage("betaQuestionDismissed") private var legacyDismissed = false

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

    private var answered: Set<String> {
        var ids = Set(answeredRaw.split(separator: ",").map(String.init))
        // A pre-existing dismissal only ever meant the first question.
        if legacyDismissed { ids.insert("before") }
        return ids
    }

    static func nextQuestion(answered: Set<String>) -> Question? {
        questions.first { !answered.contains($0.id) }
    }

    private var current: Question? { Self.nextQuestion(answered: answered) }

    private func markAnswered(_ question: Question) {
        var ids = answered
        ids.insert(question.id)
        // Sorted so the stored value is stable and legible in a defaults dump.
        answeredRaw = ids.sorted().joined(separator: ",")
    }

    private func answerButton(_ question: Question) -> some View {
        Button("Answer on the web") {
            // The id rides along so an answer can be tied to the question that
            // prompted it. The form ignores what it doesn't know.
            if let url = URL(string:
                "https://levelselect.app/invite/?tester=1&q=\(question.id)") {
                openURL(url)
            }
            markAnswered(question)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
    }

    private func declineButton(_ question: Question) -> some View {
        Button("No thanks") { markAnswered(question) }
            .buttonStyle(.bordered)
            .controlSize(.small)
    }

    var body: some View {
        if Self.isBetaInstall, let question = current {
            VStack(alignment: .leading, spacing: 10) {
                Label("One question from the developer", systemImage: "hand.wave")
                    .font(.subheadline.weight(.semibold))
                // Asks ONE thing, matching the title. Earlier copy promised
                // "two questions on the web" under a heading that said one,
                // and the form has five — a count is a promise that goes stale
                // the moment a question is added.
                Text(question.prompt + "\n\nThe app collects nothing about you. "
                     + "No analytics, no telemetry, nothing phoning home. "
                     + "Asking is the only way I'd ever find out.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                // `ViewThatFits` measures rather than guessing a breakpoint:
                // side by side while both labels fit, stacked when they don't.
                ViewThatFits(in: .horizontal) {
                    HStack { answerButton(question); declineButton(question) }
                    VStack(alignment: .leading, spacing: 8) {
                        answerButton(question); declineButton(question)
                    }
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
