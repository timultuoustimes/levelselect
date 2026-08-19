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
    /// ONE presentation slot for both prompts.
    ///
    /// Two `.sheet` modifiers on the same view is a SwiftUI trap: only one is
    /// honoured, so adding the retrospective prompt silently swallowed the
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

        var id: String {
            switch self {
            case .live(let target): "live-\(target.id.uuidString)"
            case .finished(let pair): "finished-\(pair.id)"
            }
        }
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
                }
            }
    }

    private func showLiveIfNeeded() {
        guard prompt == nil, let target = overlap else { return }
        prompt = .live(target)
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
        .presentationDetents([.medium, .large])
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
        .presentationDetents([.medium, .large])
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
