import SwiftUI
import SwiftData

/// Being told a game you are waiting for has arrived.
///
/// Third of the release arc, after the countdown on the card and the Coming
/// Soon widget. Both of those only speak when you look at them, which is fine
/// for a date months out and useless on the morning of — the whole point of
/// waiting for something is that you are not thinking about it.
///
/// Device-local on purpose. A local notification is scheduled by one device,
/// so which device tells you is already a per-device fact, and this needs no
/// schema field behind a CloudKit deploy to say it.
struct ReleaseRemindersSettings: View {
    @Query(filter: #Predicate<Game> { $0.deletedAt == nil })
    private var games: [Game]

    @State private var on = NotificationManager.releaseRemindersOn
    @State private var leadDays = NotificationManager.releaseLeadDays
    @State private var breaksThrough = NotificationManager.breaksThroughFocus
    /// The session-note prompt's own switch — see `SessionNotePrompt`.
    @AppStorage("askForSessionNotes") private var askForNotes = true

    /// What the setting will actually do, counted from the wishlist.
    private var upcoming: [Game] {
        WishlistShelf.comingSoon(games.filter { $0.status == .wishlist })
    }

    var body: some View {
        Section {
            Toggle("Tell me when a game arrives", isOn: $on)
                .tint(LSTheme.accent)
                .onChange(of: on) { _, value in
                    NotificationManager.releaseRemindersOn = value
                    if value { NotificationManager.requestAuthorizationIfNeeded() }
                    reschedule()
                }

            if on {
                Picker("Let me know", selection: $leadDays) {
                    Text("On the day").tag(0)
                    Text("A day before").tag(1)
                    Text("Three days before").tag(3)
                    Text("A week before").tag(7)
                }
                .onChange(of: leadDays) { _, value in
                    NotificationManager.releaseLeadDays = value
                    reschedule()
                }
            }
            // Not a notification, and sits here anyway: it is the other
            // thing the app says to you unprompted, and a person looking for
            // "stop asking me things" looks in one place, not two.
            Toggle("Ask what happened after I play", isOn: $askForNotes)
                .tint(LSTheme.accent)

            // Governs the still-playing reminder too, which is why it sits
            // outside the release toggle: that one is scheduled whenever a
            // timer runs, so hiding this behind "tell me when a game arrives"
            // would bury the only control over it.
            Toggle("Break through silent mode and Focus", isOn: $breaksThrough)
                .tint(LSTheme.accent)
                .onChange(of: breaksThrough) { _, value in
                    NotificationManager.breaksThroughFocus = value
                    reschedule()
                }
        } header: {
            Text("Notifications")
        } footer: {
            if on {
                // The count is the honest answer to "will this ever fire".
                // A reminder setting with nothing to remind you about should
                // say so rather than imply a promise it cannot keep.
                Text(upcoming.isEmpty
                     ? "Nothing on your wishlist has an announced date yet. Games with a real date still ahead get a reminder at 9am."
                     : "^[\(upcoming.count) game](inflect: true) on your wishlist ^[is](inflect: true) waiting. Reminders arrive at 9am, and follow the date if it moves.")
            } else {
                Text("A game you are waiting for is the one thing the app knows about before you do.")
            }
            Text("Breaking through applies to the still-playing reminder as well. iOS asks separately before it will allow it.")
        }
    }

    private func reschedule() {
        NotificationManager.syncReleaseReminders(
            upcoming: upcoming.compactMap { game in
                guard let date = game.effectiveReleaseDate else { return nil }
                return (id: game.id, name: game.name, releaseDate: date)
            })
    }
}
