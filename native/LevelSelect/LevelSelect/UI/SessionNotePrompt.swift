import SwiftUI
import SwiftData

/// Asked once, right after you stop playing.
///
/// `Session.notes` has existed since build one and has been reachable only by
/// opening a *finished* session and editing it — which is to say, by deciding
/// in advance that you wanted to write something and then going to look for
/// where. Nobody does that. The field is the journal's raw material and it is
/// empty, so the timeline built on top of it would have dates and no writing.
///
/// A guard on the tree rather than a hook at the stop, for the same reason
/// `StaleSessionGuard` and `ReleaseRemindersPrompt` are: a session is stopped
/// from **seven** places — the timers strip, the game page, the context menu,
/// an App Intent, the session controls, the Live Activity, and the watch — and
/// a hook would have to be added to each and remembered at the eighth.
///
/// **Deliberately not a nag.** It asks about a session that just ended, once,
/// and never about history. The journal research is explicit that a journal is
/// partial and that is fine — *"no completion meters on metadata, no nagging
/// to fill in a review"* — so a session you did not write about is simply a
/// session you did not write about, and nothing in the app will bring it up.
struct SessionNotePrompt: ViewModifier {
    /// How recently it must have ended for the question to be worth asking.
    ///
    /// The value is doing real work. "What happened?" is a good question about
    /// the thing you were doing ten minutes ago and a bad one about last
    /// Tuesday, so the window is what stops a helpful prompt becoming an
    /// interrogation about your back catalogue. It is generous enough to catch
    /// a session stopped on the watch or from the Live Activity, which is most
    /// of the ways a session ends without the app in front of you.
    static let window: TimeInterval = 15 * 60

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(filter: #Predicate<Game> { $0.deletedAt == nil })
    private var games: [Game]

    @AppStorage("askForSessionNotes") private var asking = true
    /// Everything ended on or before this has had its turn. One number rather
    /// than a growing set of ids, and it survives relaunch — without it,
    /// quitting and reopening would ask about the same session again.
    @AppStorage("sessionNoteWatermark") private var watermark: Double = 0

    @State private var subject: Session?
    @State private var draft = ""

    func body(content: Content) -> some View {
        content
            .onAppear { check() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { check() }
            }
            // Sessions end while the app is open, too — from the strip, the
            // game page, or the Live Activity's stop button.
            .onChange(of: latestEnding) { _, _ in check() }
            .alert("What happened?", isPresented: isPresented, presenting: subject) { session in
                TextField("One line is plenty", text: $draft)
                Button("Save") { save(to: session) }
                // Not "Cancel": nothing is being cancelled, and the choice not
                // to write is a normal answer rather than backing out.
                Button("Skip", role: .cancel) { subject = nil }
            } message: { session in
                Text(subtitle(for: session))
            }
    }

    /// Changes whenever any session finishes, so the guard re-checks without
    /// polling and without any of the seven stop sites knowing it exists.
    private var endedSessions: [Session] {
        games.flatMap { $0.livePlaythroughs.flatMap { $0.sessions ?? [] } }
    }

    private var latestEnding: Date? {
        endedSessions.compactMap(\.endDate).max()
    }

    private var isPresented: Binding<Bool> {
        Binding(get: { subject != nil }, set: { if !$0 { subject = nil } })
    }

    private func subtitle(for session: Session) -> String {
        let name = session.playthrough?.game?.name ?? "That session"
        return "\(name), \(Format.duration(session.elapsed())). "
             + "You can always add this later from the session itself."
    }

    /// Which session — if any — is worth asking about.
    ///
    /// Static and pure so the rules can be tested without a view tree; every
    /// one of them is a judgement about when a question is welcome, which is
    /// precisely the sort of thing that gets quietly loosened later.
    static func candidate(among sessions: [Session],
                          watermark: Double,
                          now: Date = .now) -> Session? {
        let cutoff = now.addingTimeInterval(-window)
        return sessions
            .filter { session in
                guard session.deletedAt == nil else { return false }
                // A running session has not ended, so there is nothing to ask
                // about yet.
                guard let ended = session.endDate else { return false }
                // Already written about is already answered.
                guard session.notes?.journalText == nil else { return false }
                return ended > cutoff
                    && ended.timeIntervalSinceReferenceDate > watermark
            }
            // The one you just finished, when several ended in the window.
            .max { ($0.endDate ?? .distantPast) < ($1.endDate ?? .distantPast) }
    }

    private func check() {
        guard asking, subject == nil else { return }
        let candidate = Self.candidate(among: endedSessions, watermark: watermark)
        guard let candidate, let ended = candidate.endDate else { return }
        // Claimed before it is shown, so a second pass — a scene change while
        // the alert is up — cannot queue the same session twice.
        watermark = ended.timeIntervalSinceReferenceDate
        draft = ""
        subject = candidate
    }

    private func save(to session: Session) {
        defer { subject = nil }
        guard let text = draft.journalText else { return }
        // Through the repository rather than by assignment, so the write is
        // revisioned and syncs like every other edit to a session — and
        // through the notes-only path, because `updateSession` would recompute
        // the duration and inflate a session that had been paused.
        Repository(context).setSessionNotes(session, text)
    }
}

extension View {
    func sessionNotePrompt() -> some View { modifier(SessionNotePrompt()) }
}
