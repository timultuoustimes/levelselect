import SwiftUI
import SwiftData

/// Surfaces two devices timing the same game, and lets the user resolve it.
///
/// This replaces a silent decision. The app used to pick a winner by a rule
/// nobody had seen and close the other timer — and when the rule was wrong,
/// the first sign was a stopped timer someone was still watching. Now the
/// conflict is shown, with enough detail to actually choose: which device,
/// when it started, how much time it has.
///
/// Nothing is closed until the user says so (under the default `ask` policy),
/// so the cost of an unanswered prompt is doubled playtime in totals rather
/// than lost time — visible and recoverable, instead of silent and not.
struct OverlappingTimerGuard: ViewModifier {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Session> { $0.endDate == nil && $0.deletedAt == nil })
    private var unstopped: [Session]

    /// Games the user chose to leave alone this launch, so declining doesn't
    /// re-ask on every foreground.
    @State private var dismissed: Set<UUID> = []
    /// Sets of games the user has said "keep both" to, this launch.
    @State private var dismissedCrossGame: Set<String> = []
    /// ONE presentation slot for both prompts.
    ///
    /// Two `.sheet` modifiers on the same view is a SwiftUI trap: only one is
    /// honored, so adding the retrospective prompt silently swallowed the
    /// live one — the guard looked fine, ran its detection correctly, and
    /// simply never appeared. A single slot with a case per prompt makes that
    /// impossible to reintroduce.
    @State private var prompt: ActivePrompt?
    /// Finished-session pairs the user has settled. Device-local on purpose:
    /// it records a UI decision, not data, and the worst case if another
    /// device hasn't heard is being asked once more there.
    @AppStorage("settledSessionOverlaps") private var settledRaw = ""

    private var repo: Repository { Repository(context) }

    /// A game with more than one running timer.
    struct OverlapTarget: Identifiable {
        let game: Game
        let sessions: [Session]
        var id: UUID { game.id }
    }

    private var overlap: OverlapTarget? {
        guard repo.overlappingTimerPolicy == .ask else { return nil }
        let running = unstopped.filter {
            $0.state == .running
                && $0.playthrough?.deletedAt == nil
                && $0.playthrough?.game?.deletedAt == nil
        }
        let byGame = Dictionary(grouping: running) { $0.playthrough?.game?.id }
        for (gameID, sessions) in byGame {
            guard let gameID, sessions.count > 1,
                  !dismissed.contains(gameID),
                  let game = sessions.first?.playthrough?.game
            else { continue }
            return OverlapTarget(
                game: game,
                sessions: sessions.sorted {
                    ($0.lastUserAction, $0.id.uuidString) > ($1.lastUserAction, $1.id.uuidString)
                })
        }
        return nil
    }

    /// A finished-session overlap worth asking about — only once the live
    /// case is settled, since a timer still running is the urgent one, and
    /// never when the user has said to keep both.
    private var finishedOverlap: Repository.SessionOverlap? {
        guard overlap == nil, prompt == nil,
              repo.overlappingTimerPolicy != .keepBoth
        else { return nil }
        let settled = Set(settledRaw.split(separator: "\n").map(String.init))
        return repo.overlappingFinishedSessions().first { !settled.contains($0.id) }
    }

    enum ActivePrompt: Identifiable {
        case live(OverlapTarget)
        case finished(Repository.SessionOverlap)
        case crossGame([Session])

        var id: String {
            switch self {
            case .live(let target): "live-\(target.id.uuidString)"
            case .finished(let pair): "finished-\(pair.id)"
            case .crossGame(let sessions):
                "cross-" + sessions.map(\.id.uuidString).sorted().joined(separator: "+")
            }
        }
    }

    /// **Two games at once, on this device.**
    ///
    /// The guard above is about ONE game timed on TWO devices — a sync
    /// problem. This is the everyday mistake: you start Hades without having
    /// stopped Hollow Knight, and both accrue. Tim, when it went unremarked:
    /// *"starting a second timer prompts something like 'you have a timer
    /// running for x game at y amount of time. Stop timer before starting this
    /// one? Keep other timer running?'"*
    ///
    /// Detected here rather than hooked into `startSession`, for the same
    /// reason every other guard in this app is a guard: a timer starts from
    /// the game page, the context menu, the timers strip, an App Intent, the
    /// Live Activity, a widget and the watch, and a hook would have to be
    /// added to each and remembered at the eighth. A device that starts one on
    /// the watch gets asked here the moment the phone is opened.
    ///
    /// Not forced: two games at once is unusual rather than wrong, so "Keep
    /// both" is a real answer and the prompt does not return this launch.
    private var crossGame: [Session]? {
        Self.crossGameSessions(among: unstopped, dismissed: dismissedCrossGame)
    }

    /// Static so it can be tested without a view. Same reason
    /// `SessionNotePrompt.candidate` is: the rule is the part that can be
    /// wrong, and it should not need a running app to check.
    static func crossGameSessions(among sessions: [Session],
                                  dismissed: Set<String>) -> [Session]? {
        let running = sessions.filter {
            $0.state == .running
                && $0.endDate == nil
                && $0.deletedAt == nil
                && $0.playthrough?.deletedAt == nil
                && $0.playthrough?.game?.deletedAt == nil
        }
        let byGame = Dictionary(grouping: running) { $0.playthrough?.game?.id }
        // The same-game conflict above owns that case; this one is only about
        // DIFFERENT games, so a game timed twice is left to it.
        guard byGame.values.allSatisfy({ $0.count == 1 }), byGame.count > 1 else {
            return nil
        }
        guard !dismissed.contains(key(for: running)) else { return nil }
        // Oldest first: the one you forgot leads, because it is the one being
        // asked about.
        return running.sorted { $0.startDate < $1.startDate }
    }

    /// The set of games, as one stable string — so "keep both" is remembered
    /// for THIS pair and a third game asks again.
    static func key(for sessions: [Session]) -> String {
        sessions
            .compactMap { $0.playthrough?.game?.id.uuidString }
            .sorted()
            .joined(separator: "+")
    }

    /// Changes whenever the set of running timers does — including a state
    /// flip that leaves `endDate` nil, which a plain count would miss.
    private var runningSignature: String {
        unstopped
            .filter { $0.state == .running }
            .map(\.id.uuidString)
            .sorted()
            .joined(separator: ",")
    }

    func body(content: Content) -> some View {
        content
            .onAppear { showLiveIfNeeded() }
            .onChange(of: runningSignature) { _, _ in showLiveIfNeeded() }
            // Retrospective, so it waits for a quiet moment rather than
            // interrupting a launch: only once nothing live is pending, and
            // only for pairs never settled before.
            .task(id: runningSignature) {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, prompt == nil,
                      let pair = finishedOverlap else { return }
                prompt = .finished(pair)
            }
            .sheet(item: $prompt) { active in
                switch active {
                case .live(let target):
                    OverlappingTimerSheet(target: target) { resolution in
                        apply(resolution, to: target)
                    }
                case .finished(let pair):
                    FinishedOverlapSheet(pair: pair) { resolution in
                        applyFinished(resolution, to: pair)
                    }
                case .crossGame(let sessions):
                    CrossGameTimerSheet(sessions: sessions) { stopping in
                        applyCrossGame(stopping, among: sessions)
                    }
                }
            }
    }

    private func showLiveIfNeeded() {
        // Answered on the other device? Take this copy of the question down.
        //
        // Both devices raise this prompt for the same conflict, so resolving
        // on one leaves a stale sheet on the other describing a conflict that
        // no longer exists — and acting on it would stop the very timer the
        // user just chose to keep.
        if case .live(let showing) = prompt,
           repo.runningSessions(in: showing.game).count < 2 {
            prompt = nil
        }
        if case .crossGame = prompt, crossGame == nil { prompt = nil }
        guard prompt == nil else { return }
        // Same-game first: it is a data problem, and the cross-game question
        // is only interesting once each game is timed once.
        if let target = overlap {
            prompt = .live(target)
        } else if let sessions = crossGame {
            prompt = .crossGame(sessions)
        }
    }

    /// `nil` means keep both — remembered for this launch so the answer is
    /// taken as an answer rather than re-asked on every foreground.
    private func applyCrossGame(_ stopping: Session?, among sessions: [Session]) {
        if let stopping {
            repo.stopSession(stopping)
        } else {
            dismissedCrossGame.insert(Self.key(for: sessions))
        }
        prompt = nil
    }

    private func applyFinished(_ resolution: FinishedOverlapResolution,
                               to pair: Repository.SessionOverlap) {
        switch resolution {
        case .remove(let session):
            // Tombstoned, not erased: it drops out of totals and history but
            // the record survives, because "this looks like a duplicate" is
            // never certain enough to destroy someone's recorded time.
            repo.deleteSession(session)
        case .removeBoth:
            repo.deleteSession(pair.first)
            repo.deleteSession(pair.second)
        case .keepBoth:
            break
        }
        settle(pair)
        prompt = nil
    }

    /// Remember that this pair has been dealt with, so it is never raised
    /// again whichever way it was answered.
    private func settle(_ pair: Repository.SessionOverlap) {
        var ids = settledRaw.split(separator: "\n").map(String.init)
        guard !ids.contains(pair.id) else { return }
        ids.append(pair.id)
        // Bounded, so a long-lived install can't grow this without limit.
        settledRaw = ids.suffix(200).joined(separator: "\n")
    }

    private func apply(_ resolution: OverlapResolution, to target: OverlapTarget) {
        switch resolution {
        case .keep(let session, let remember):
            repo.keepOnlyRunningSession(session, in: target.game)
            // "Always" only means something when the choice maps to a rule.
            // Keeping the most recent is a rule; keeping a specific older
            // timer is a judgement about this moment, so the sheet doesn't
            // offer to repeat it.
            if remember { repo.setOverlappingTimerPolicy(.keepNewest) }
        case .keepBoth(let remember):
            dismissed.insert(target.game.id)
            if remember { repo.setOverlappingTimerPolicy(.keepBoth) }
        }
        prompt = nil
    }
}

enum OverlapResolution {
    case keep(Session, remember: Bool)
    case keepBoth(remember: Bool)
}

/// The chooser. Deliberately a sheet rather than an alert: this is a decision
/// about someone's recorded time, and it needs room to say which device,
/// when, and how much — an alert's two lines can't.
private struct OverlappingTimerSheet: View {
    let target: OverlappingTimerGuard.OverlapTarget
    let onResolve: (OverlapResolution) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var remember = false

    /// The one the app would pick on its own — offered as the recommendation
    /// rather than applied behind the user's back.
    private var recommended: Session? { target.sessions.first }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("\(target.game.name) has a timer running on more than one device. Their time is being counted separately until you choose.")
                        .font(.subheadline)
                }

                Section {
                    ForEach(target.sessions) { session in
                        Button {
                            onResolve(.keep(session, remember: remember && session === recommended))
                            dismiss()
                        } label: {
                            timerRow(session)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Keep one")
                } footer: {
                    Text("The other timer stops, keeping the time it earned up to the moment this one started — so the overlap isn't counted twice.")
                }

                Section {
                    Button {
                        onResolve(.keepBoth(remember: remember))
                        dismiss()
                    } label: {
                        Label("Keep both running", systemImage: "arrow.triangle.branch")
                    }
                } footer: {
                    Text("Leaves both alone. Useful if two people really are playing; their time adds up separately.")
                }

                Section {
                    Toggle("Always do this", isOn: $remember)
                } footer: {
                    Text("Applies to keeping the most recent timer, or keeping both. Change it any time in Settings → iCloud.")
                }
            }
            .navigationTitle("Two timers running")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                }
            }
        }
        .lsSheet()
    }

    private func timerRow(_ session: Session) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "stopwatch")
                .foregroundStyle(LSTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    // The device name is why Schema V2 exists: "another
                    // device" is useless when the whole question is which one.
                    Text(session.originDevice ?? "Another device")
                        .font(.subheadline.weight(.semibold))
                    if session === recommended {
                        Text("MOST RECENT")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(LSTheme.accent.opacity(0.2), in: .capsule)
                            .foregroundStyle(LSTheme.accent)
                    }
                }
                Text("Started \(session.startDate, format: .dateTime.month().day().hour().minute())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(Format.duration(session.elapsed()))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .contentShape(.rect)
    }
}

extension View {
    func overlappingTimerGuard() -> some View { modifier(OverlappingTimerGuard()) }
}

enum FinishedOverlapResolution {
    case remove(Session)
    case removeBoth
    case keepBoth
}

/// Two finished sessions claiming the same minutes. Retrospective, so the
/// wording is careful: this is a question about records the user already has,
/// and the app genuinely cannot tell whether the overlap is double-counted
/// time or two people playing — a paused session can span another's without
/// costing a single minute.
private struct FinishedOverlapSheet: View {
    let pair: Repository.SessionOverlap
    let onResolve: (FinishedOverlapResolution) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Two sessions for \(pair.game.name) cover the same \(Format.duration(pair.seconds)) — recorded on different devices. If both are real, your total counts that time twice.")
                        .font(.subheadline)
                }

                Section {
                    ForEach([pair.first, pair.second], id: \.id) { session in
                        sessionRow(session)
                    }
                } header: {
                    Text("The two sessions")
                }

                Section {
                    Button {
                        onResolve(.remove(pair.second)); dismiss()
                    } label: {
                        Label("Keep \(name(pair.first))'s only", systemImage: "1.circle")
                    }
                    Button {
                        onResolve(.remove(pair.first)); dismiss()
                    } label: {
                        Label("Keep \(name(pair.second))'s only", systemImage: "2.circle")
                    }
                    Button {
                        onResolve(.keepBoth); dismiss()
                    } label: {
                        Label("Keep both", systemImage: "checkmark.circle")
                    }
                    Button(role: .destructive) {
                        onResolve(.removeBoth); dismiss()
                    } label: {
                        Label("Remove both", systemImage: "trash")
                    }
                } footer: {
                    Text("Removed sessions leave your totals and history but aren't erased. Whatever you choose, this pair won't be raised again.")
                }
            }
            .navigationTitle("Overlapping sessions")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                }
            }
        }
        .lsSheet()
    }

    private func name(_ session: Session) -> String {
        session.originDevice ?? "Another device"
    }

    private func sessionRow(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name(session)).font(.subheadline.weight(.semibold))
            HStack(spacing: 4) {
                Text(session.startDate, format: .dateTime.month().day().hour().minute())
                if let end = session.endDate {
                    Text("→")
                    Text(end, format: .dateTime.hour().minute())
                }
                Text("·")
                Text(Format.duration(session.elapsed()))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}


/// Two games timing at once, on this device.
///
/// Deliberately not a three-button alert: the useful information is WHICH
/// game and HOW LONG, and an alert cannot carry two rows of that. Stopping
/// one credits its time normally — the same stop as any other, so the
/// post-session "What happened?" follows it.
private struct CrossGameTimerSheet: View {
    let sessions: [Session]
    /// nil = keep both.
    let onResolve: (Session?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Two games are timing at once. Both are counting, so their playtime is being recorded separately until you stop one.")
                        .font(.subheadline)
                }

                Section {
                    ForEach(sessions) { session in
                        Button {
                            onResolve(session)
                            dismiss()
                        } label: {
                            HStack(spacing: 11) {
                                CoverThumb(urlString: session.playthrough?.game?.displayCoverURLString,
                                           artwork: session.playthrough?.game?.resolvedArtwork(.cover),
                                           name: session.playthrough?.game?.name ?? "",
                                           status: session.playthrough?.game?.status ?? .playing)
                                    .frame(width: 34, height: 46)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.playthrough?.game?.name ?? "A game")
                                        .font(.subheadline.weight(.semibold))
                                    Text("\(Format.duration(session.elapsed())) · started \(session.startDate.formatted(date: .omitted, time: .shortened))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "stop.fill")
                                    .foregroundStyle(LSTheme.accent)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Stop one")
                } footer: {
                    Text("Its time is credited the way any stop is.")
                }

                Section {
                    Button("Keep both running") {
                        onResolve(nil)
                        dismiss()
                    }
                } footer: {
                    Text("Sometimes two at once is the truth. You won't be asked again until the next launch.")
                }
            }
            .navigationTitle("Two timers running")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .lsSheet()
    }
}
