import SwiftUI
import SwiftData

/// Offered once, at the only moment it means anything.
///
/// Release reminders are off until asked for, and a switch in Settings nobody
/// has a reason to look for is a feature that ships and never runs. The moment
/// it stops being abstract is the moment there is a first game with a real
/// date ahead of it — that is when "shall I tell you when this arrives" is a
/// question about something rather than a setting.
///
/// A guard rather than a hook on the add sheet, for the same reason the stale
/// session one is: a wishlist game can arrive from Deku Deals, from an import,
/// or from another device over CloudKit, and none of those go through the add
/// screen. This watches the wishlist itself, so it fires however the game got
/// there.
struct ReleaseRemindersPrompt: ViewModifier {
    @Query(filter: #Predicate<Game> { $0.deletedAt == nil })
    private var games: [Game]

    /// Asked once, ever. Someone who says no is not asked again — the switch
    /// is in Settings for anyone who changes their mind, and a prompt that
    /// returns is an app arguing with a decision it already heard.
    @AppStorage("askedAboutReleaseReminders") private var asked = false
    @State private var showing = false

    private var firstUpcoming: Game? {
        WishlistShelf.comingSoon(games.filter { $0.status == .wishlist }).first
    }

    func body(content: Content) -> some View {
        content
            .task(id: firstUpcoming?.id) { evaluate() }
            .alert("Tell you when it arrives?",
                   isPresented: $showing, presenting: firstUpcoming) { _ in
                Button("Yes, remind me") {
                    NotificationManager.releaseRemindersOn = true
                    NotificationManager.requestAuthorizationIfNeeded()
                    reschedule()
                }
                Button("Not now", role: .cancel) {}
            } message: { game in
                Text(message(for: game))
            }
    }

    private func evaluate() {
        guard !asked,
              !NotificationManager.releaseRemindersOn,
              let game = firstUpcoming,
              let date = game.effectiveReleaseDate,
              ReleaseCountdown.countdown(to: date) != nil
        else { return }
        asked = true
        showing = true
    }

    private func message(for game: Game) -> String {
        guard let date = game.effectiveReleaseDate,
              let soon = ReleaseCountdown.countdown(to: date) else {
            return "\(game.name) is the first thing on your wishlist with a release date."
        }
        // Names the game and the wait, because "enable notifications?" asks
        // you to imagine the value and this asks about a thing you just added.
        return "\(game.name) lands \(soon) — \(ReleaseCountdown.dateLabel(date)). "
             + "LevelSelect can say something the morning before. You can change the timing in Settings."
    }

    private func reschedule() {
        NotificationManager.syncReleaseReminders(
            upcoming: WishlistShelf
                .comingSoon(games.filter { $0.status == .wishlist })
                .compactMap { game in
                    guard let date = game.effectiveReleaseDate else { return nil }
                    return (id: game.id, name: game.name, releaseDate: date)
                })
    }
}

extension View {
    func releaseRemindersPrompt() -> some View { modifier(ReleaseRemindersPrompt()) }
}
