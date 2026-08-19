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
    @State private var resolving: OverlapTarget?

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

    func body(content: Content) -> some View {
        content
            .onChange(of: overlap?.id) { _, _ in
                if resolving == nil { resolving = overlap }
            }
            .onAppear { resolving = overlap }
            .sheet(item: $resolving) { target in
                OverlappingTimerSheet(target: target) { resolution in
                    apply(resolution, to: target)
                }
            }
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
        resolving = nil
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
