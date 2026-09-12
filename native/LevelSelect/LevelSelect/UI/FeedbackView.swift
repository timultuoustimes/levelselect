import SwiftUI
import SwiftData

/// Send feedback — the whole of it, without leaving the app.
///
/// This replaces three links out to a browser and one instruction to go find
/// TestFlight. Tim, looking at Gamery's: *"I love the fact that gamery lets
/// users send an email to the developer directly from within the app, and it
/// pulls the logs."* We can do the same and better on the privacy half: their
/// logs come from Sentry, collecting quietly in the background. Ours are
/// assembled when you tap, shown to you in full before they go, and sent by
/// you from your own mail account.
///
/// Three kinds rather than one, because "report a problem" is the narrowest of
/// the three things people actually want to say, and a subject line that
/// already says which one lands in a mailbox that can be triaged.
struct FeedbackView: View {
    /// Seeds the message — used by the beta question card, which arrives here
    /// with its question already in the body.
    var kind: Kind = .problem
    var seededMessage: String = ""
    var seededSubjectDetail: String?

    enum Kind: String, CaseIterable, Identifiable {
        case problem, idea, question
        var id: String { rawValue }

        var label: String {
            switch self {
            case .problem:  "Problem"
            case .idea:     "Idea"
            case .question: "Question"
            }
        }
        /// What the box is asking for. A blank field with no prompt gets blank
        /// answers; naming the useful shape of an answer is most of the work.
        var prompt: String {
            switch self {
            case .problem:  "What happened, and what did you expect instead?"
            case .idea:     "What would you like it to do?"
            case .question: "What would you like to know?"
            }
        }
        var blurb: String {
            switch self {
            case .problem:
                "Goes straight to Tim. Nothing is sent until you tap Send, and you can read every word that goes with it."
            case .idea:
                "There's no roadmap committee. Ideas from people using the app are most of what ends up getting built."
            case .question:
                "Ask anything about the app — how something works, or why it works that way."
            }
        }
        var icon: String {
            switch self {
            case .problem:  "ladybug"
            case .idea:     "lightbulb"
            case .question: "questionmark.bubble"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Query(filter: #Predicate<Game> { $0.deletedAt == nil }) private var games: [Game]
    @Query(filter: #Predicate<Session> { $0.deletedAt == nil }) private var sessions: [Session]
    @Query(sort: \ThemeSettings.createdAt) private var themeSettings: [ThemeSettings]

    @State private var selectedKind: Kind?
    @State private var message = ""
    @State private var includeDiagnostics = true
    @State private var showingDiagnostics = false
    @State private var composing = false
    /// Send was tapped before the log finished. Shown on the button so the tap
    /// is visibly doing something.
    @State private var preparing = false
    @State private var result: String?
    /// nil until the log has been read. Reading it is the one slow part of
    /// this screen — see `Diagnostics.recentLog` — so it happens off the main
    /// actor and the section says it is working until it lands.
    @State private var log: String?
    @State private var logTask: Task<String, Never>?

    private var kindInUse: Kind { selectedKind ?? kind }
    private var trimmed: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        SettingsPage(title: "Send feedback",
                     icon: kindInUse.icon,
                     blurb: kindInUse.blurb) {
            Section {
                Picker("Kind", selection: Binding(
                    get: { kindInUse },
                    set: { selectedKind = $0 })) {
                    ForEach(Kind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                // `axis: .vertical` rather than a TextEditor: it grows with
                // what's typed, keeps the Form's own row styling, and shows a
                // real placeholder — which a TextEditor still cannot do.
                TextField(kindInUse.prompt, text: $message, axis: .vertical)
                    .lineLimit(4...12)
            }

            Section {
                Toggle("Include diagnostics", isOn: $includeDiagnostics)
                    .tint(LSTheme.accent)
                if includeDiagnostics {
                    DisclosureGroup("What gets sent", isExpanded: $showingDiagnostics) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(diagnosticsSummary)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                            if let log {
                                Text(log)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            } else {
                                // A spinner rather than nothing: an empty
                                // space under a heading called "What gets
                                // sent" reads as "nothing does".
                                HStack(spacing: 8) {
                                    ProgressView().controlSize(.small)
                                    Text("Reading this launch's log…")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                    }
                }
            } footer: {
                // The exact claim, because it is the one that distinguishes
                // this from every other in-app feedback button.
                Text("Counts and this launch's log — never game titles, notes, your profile, or any key. It's assembled when you tap Send and kept nowhere. LevelSelect has no crash reporter and no analytics.")
            }

            Section {
                Button {
                    send()
                } label: {
                    if preparing {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Preparing…")
                        }
                    } else {
                        Label(sendLabel, systemImage: "paperplane")
                    }
                }
                .disabled(trimmed.isEmpty || preparing)

                Button {
                    Mail.copyToClipboard("To: \(Mail.feedbackAddress)\nSubject: \(subject)\n\n\(messageBody)")
                    result = "Copied. Paste it into a mail to \(Mail.feedbackAddress)."
                } label: {
                    Label("Copy instead", systemImage: "doc.on.doc")
                }
                .disabled(trimmed.isEmpty)

                if let result {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Goes to \(Mail.feedbackAddress) from your own mail account, so the reply comes back to your own inbox. There's no account here and no ticket number to lose.")
            }
        }
        .task {
            if message.isEmpty { message = seededMessage }
            // Detached, because this screen must appear instantly and the log
            // read is slow enough to be felt — it was seven seconds before the
            // window narrowed and this moved off the main actor. Started as
            // soon as the screen opens so it is almost always ready by the
            // time anyone has typed a sentence.
            guard logTask == nil else { return }
            let task = Task.detached(priority: .userInitiated) {
                Diagnostics.recentLog()
            }
            logTask = task
            log = await task.value
        }
        #if os(iOS)
        .sheet(isPresented: $composing) {
            MailComposeSheet(to: Mail.feedbackAddress,
                             subject: subject,
                             body: messageBody) { sent in
                if sent {
                    result = "Sent. Thank you — I read every one of these."
                    message = ""
                }
            }
            .ignoresSafeArea()
        }
        #endif
    }

    private var sendLabel: String {
        Mail.canComposeInApp ? "Send" : "Send in Mail"
    }

    private var subject: String {
        var parts = ["LevelSelect \(Diagnostics.versionString)", kindInUse.label]
        if let seededSubjectDetail { parts.append(seededSubjectDetail) }
        return parts.joined(separator: " — ")
    }

    private var diagnosticsText: String {
        guard let log else { return diagnosticsSummary }
        return diagnosticsSummary + "\n\n" + log
    }

    private var diagnosticsSummary: String {
        Diagnostics.summary(
            games: games.count,
            sessions: sessions.count,
            sync: SyncStatusMonitor.shared.shortStatus,
            services: connectedServices,
            appearance: LSAppearance(raw: themeSettings.first?.appearanceRaw).label)
    }

    private var connectedServices: [String] {
        var names: [String] = []
        if RACredentials.isConfigured { names.append("RetroAchievements") }
        if ItchCredentials.isConfigured { names.append("itch.io") }
        return names
    }

    /// Inline rather than attached, on every path.
    ///
    /// An attachment only works in the in-app composer, and the `mailto:`
    /// fallback would have silently dropped it — a report that arrives without
    /// the half that explains it is worse than one that is a bit long.
    private var messageBody: String {
        guard includeDiagnostics else { return trimmed + "\n" }
        return trimmed + "\n\n—\n" + diagnosticsText + "\n"
    }

    private func send() {
        result = nil
        // If the log has not landed yet, wait for it rather than sending a
        // report with the half that explains the bug quietly missing.
        if includeDiagnostics, log == nil, let logTask {
            preparing = true
            Task {
                log = await logTask.value
                preparing = false
                send()
            }
            return
        }
        #if os(iOS)
        if Mail.canComposeInApp {
            composing = true
            return
        }
        #endif
        if !Mail.openInMailApp(to: Mail.feedbackAddress,
                               subject: subject, body: messageBody) {
            Mail.copyToClipboard("To: \(Mail.feedbackAddress)\nSubject: \(subject)\n\n\(messageBody)")
            result = "No mail app here — copied it to the clipboard instead, addressed to \(Mail.feedbackAddress)."
        }
    }
}
