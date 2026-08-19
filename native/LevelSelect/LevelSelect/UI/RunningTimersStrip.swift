import SwiftUI
import SwiftData

/// Every live timer, on the first screen, with its controls.
///
/// A running session used to be invisible from Home unless it happened to be
/// the Continue Playing game: the timer ran, the total climbed, and reaching
/// it meant knowing which game to open. That is exactly how a forgotten timer
/// becomes six hours of imaginary playtime — the failure the stale-session
/// prompt exists to catch after the fact, made harder to reach beforehand.
///
/// Shows timers for games OTHER than the hero card, which has its own
/// controls; when the hero is the only one running, this disappears entirely
/// rather than repeating it.
struct RunningTimersStrip: View {
    /// The game already shown with controls in Continue Playing.
    let excluding: Game?
    var onOpen: (Game) -> Void

    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Session> {
        $0.endDate == nil && $0.deletedAt == nil
    }) private var unstopped: [Session]

    private var repo: Repository { Repository(context) }

    private var live: [Session] {
        unstopped
            .filter {
                $0.state != .stopped
                    && $0.playthrough?.deletedAt == nil
                    && $0.playthrough?.game?.deletedAt == nil
                    && $0.playthrough?.game?.id != excluding?.id
            }
            .sorted { ($0.lastUserAction, $0.id.uuidString) > ($1.lastUserAction, $1.id.uuidString) }
    }

    var body: some View {
        if !live.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(live.count == 1 ? "ALSO RUNNING" : "ALSO RUNNING (\(live.count))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .kerning(1)

                VStack(spacing: 6) {
                    ForEach(live) { session in
                        row(session)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func row(_ session: Session) -> some View {
        if let game = session.playthrough?.game {
            HStack(spacing: 10) {
                Button {
                    onOpen(game)
                } label: {
                    HStack(spacing: 10) {
                        CoverThumb(urlString: game.coverURLString)
                            .frame(width: 30, height: 40)
                            .clipShape(.rect(cornerRadius: 5))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(game.name)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                                HStack(spacing: 4) {
                                    Image(systemName: session.state == .running
                                          ? "record.circle" : "pause.circle")
                                    Text(Format.clock(session.elapsed(asOf: ctx.date)))
                                    // Naming the device matters here: a timer
                                    // you forgot is usually one you left
                                    // running somewhere else.
                                    if let device = session.originDevice {
                                        Text("· \(device)")
                                    }
                                }
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(session.state == .running
                                                 ? AnyShapeStyle(.green) : AnyShapeStyle(.orange))
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)

                Button {
                    if session.state == .running { repo.pauseSession(session) }
                    else { repo.resumeSession(session) }
                } label: {
                    Image(systemName: session.state == .running ? "pause.fill" : "play.fill")
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .background(LSTheme.accent.opacity(0.15), in: .rect(cornerRadius: 8))
                .foregroundStyle(LSTheme.accent)
                .accessibilityLabel(session.state == .running ? "Pause" : "Resume")

                Button {
                    repo.stopSession(session)
                } label: {
                    Image(systemName: "stop.fill")
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .background(.red.opacity(0.14), in: .rect(cornerRadius: 8))
                .foregroundStyle(.red.opacity(0.9))
                .accessibilityLabel("Stop")
            }
            .padding(8)
            .background(.white.opacity(0.04), in: .rect(cornerRadius: 10))
        }
    }
}
