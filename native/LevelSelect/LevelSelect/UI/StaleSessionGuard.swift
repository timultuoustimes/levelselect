import SwiftUI
import SwiftData

/// "Still playing?" watchdog. Whenever the app foregrounds, any session
/// running/paused past the threshold triggers a prompt: keep going, end
/// (time capped at the threshold — the true duration is unknowable), or
/// discard. Session state syncs via CloudKit, so whichever device you open
/// next asks — the check is cross-device by construction.
struct StaleSessionGuard: ViewModifier {
    static let threshold: TimeInterval = 6 * 3600   // 6 hours

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(filter: #Predicate<Game> { $0.deletedAt == nil })
    private var games: [Game]

    @State private var stale: Session?
    @State private var ending: Session?             // end-time sheet target
    @State private var snoozed: Set<UUID> = []      // per-launch "still playing" answers

    func body(content: Content) -> some View {
        content
            .onAppear { check() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { check() }
            }
            // "End Session…" chosen on a notification → open the sheet directly.
            .onReceive(NotificationCenter.default.publisher(for: .lsEndSessionRequested)) { note in
                guard let id = note.object as? UUID else { return }
                ending = games
                    .flatMap { $0.livePlaythroughs.flatMap { $0.sessions ?? [] } }
                    .first { $0.id == id && $0.state != .stopped }
            }
            // The prompt can be answered on ANOTHER device: open the app
            // before its discard/stop has synced and this device asks about a
            // session that is already resolved — two-device testing hit
            // exactly that (discarded on the phone, the iPad asked again
            // hours later). When the answer lands mid-prompt, take the
            // prompt down instead of asking the user to answer twice.
            .onChange(of: stale.map { $0.state == .stopped || $0.deletedAt != nil }) { _, resolved in
                if resolved == true { stale = nil }
            }
            .onChange(of: ending.map { $0.state == .stopped || $0.deletedAt != nil }) { _, resolved in
                if resolved == true { ending = nil }
            }
            .alert("Still playing?", isPresented: isPresented) {
                Button("Still Playing") {
                    if let s = stale { snoozed.insert(s.id) }
                    stale = nil
                }
                Button("End Session…") {
                    ending = stale
                    stale = nil
                }
                Button("Discard Session", role: .destructive) {
                    if let s = stale {
                        Repository(context).discardSession(s)
                    }
                    stale = nil
                    check()
                }
            } message: {
                Text(messageText)
            }
            .sheet(item: $ending) { session in
                EndSessionSheet(session: session)
            }
    }

    private var isPresented: Binding<Bool> {
        Binding(get: { stale != nil }, set: { if !$0 { stale = nil } })
    }

    private var messageText: String {
        guard let s = stale else { return "" }
        let name = s.playthrough?.game?.name ?? "A game"
        return "\(name) has a session running for \(Format.duration(s.elapsed())). "
            + "End lets you pick when you stopped; Discard records no time."
    }

    private func check() {
        let candidates = games
            .flatMap { $0.livePlaythroughs }
            .compactMap(\.activeSession)

        // Reconcile local notifications with active sessions — including
        // sessions started on other devices (arrived via CloudKit) and ones
        // resolved elsewhere.
        NotificationManager.syncReminders(
            active: candidates
                .filter { $0.state == .running }
                .map { s in
                    // Effective start such that (now − start) == true elapsed,
                    // so the reminder fires exactly at the threshold.
                    (id: s.id,
                     gameName: s.playthrough?.game?.name ?? "A game",
                     start: Date.now.addingTimeInterval(-s.elapsed()))
                },
            threshold: Self.threshold
        )

        // Release reminders reconcile in the same pass and for the same
        // reason: a wishlist game can arrive from another device, a date can
        // move, and a game can be bought — all of which happen while the app
        // is closed, and none of which the scheduling side would ever hear
        // about on its own.
        NotificationManager.syncReleaseReminders(
            upcoming: WishlistShelf
                .comingSoon(games.filter { $0.status == .wishlist })
                .compactMap { game in
                    guard let date = game.firstReleaseDate else { return nil }
                    return (id: game.id, name: game.name, releaseDate: date)
                })

        guard stale == nil else { return }
        stale = candidates.first {
            $0.elapsed() > Self.threshold && !snoozed.contains($0.id)
        }
    }
}

extension View {
    func staleSessionGuard() -> some View { modifier(StaleSessionGuard()) }
}
