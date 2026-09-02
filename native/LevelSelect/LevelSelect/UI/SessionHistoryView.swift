import SwiftUI
import SwiftData

/// Every session for a game, not just the last five.
///
/// The game page shows `sessions.prefix(5)` under "Recent — tap to edit", and
/// until now that was the ONLY list of sessions in the app. On a game you come
/// back to, sessions six and beyond still counted toward every total and were
/// unreachable — and, because that row is the only route to `EditSessionSheet`,
/// uneditable. A mistyped hour from last month could not be corrected.
///
/// It hid behind small data. With every demo game holding six sessions,
/// `prefix(5)` looked like it showed nearly everything; a realistic library —
/// 63 hours of Stardew Valley in two-hour sittings — is what made it visible.
///
/// Sessions belong to a PLAYTHROUGH, and the game page only ever shows the
/// active one, so a second playthrough's history was doubly buried. Hence the
/// filter: this is the one place that can see all of them, so it should be
/// able to show them apart.
struct SessionHistoryView: View {
    let game: Game

    @Environment(\.modelContext) private var context
    @State private var playthroughFilter: UUID?
    @State private var editing: Session?

    /// Store-driven for the same reason `SessionControlsView` is: a session
    /// synced from another device is inserted and points its to-one at the
    /// playthrough, so the playthrough's own fields never change and a
    /// relationship-derived list is never invalidated. See that view's note.
    @Query private var liveSessions: [Session]

    init(game: Game) {
        self.game = game
        let ptIDs = game.livePlaythroughs.map(\.id)
        _liveSessions = Query(
            filter: #Predicate<Session> {
                $0.deletedAt == nil && $0.playthrough.flatMap { ptIDs.contains($0.id) } == true
            },
            sort: [SortDescriptor(\Session.startDate, order: .reverse)]
        )
    }

    private var playthroughs: [Playthrough] { game.livePlaythroughs }

    private var shown: [Session] {
        guard let playthroughFilter else { return liveSessions }
        return liveSessions.filter { $0.playthrough?.id == playthroughFilter }
    }

    private var months: [SessionMonth] { SessionMonth.group(shown) }

    var body: some View {
        List {
            Section {
                summary
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 12, trailing: 0))
            }

            ForEach(months) { month in
                Section {
                    ForEach(month.sessions) { session in
                        row(session)
                    }
                } header: {
                    HStack {
                        Text(month.start, format: .dateTime.month(.wide).year())
                        Spacer()
                        // The month's own total, because "how much did I play
                        // in March" is the question a month grouping invites.
                        Text(Format.duration(month.total))
                            .monospacedDigit()
                    }
                }
            }

            if shown.isEmpty {
                ContentUnavailableView("No sessions here",
                                       systemImage: "stopwatch",
                                       description: Text(playthroughFilter == nil
                                           ? "Time a session and it will appear here."
                                           : "This playthrough has no sessions yet."))
            }
        }
        #if os(macOS)
        .listStyle(.inset)
        #endif
        .navigationTitle("Sessions")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            // Only when there is something to choose between. One playthrough
            // is the common case and a filter offering a single option is
            // furniture.
            if playthroughs.count > 1 {
                ToolbarItem {
                    Menu {
                        Picker("Playthrough", selection: $playthroughFilter) {
                            Text("All playthroughs").tag(UUID?.none)
                            ForEach(playthroughs) { pt in
                                Text(pt.name).tag(UUID?.some(pt.id))
                            }
                        }
                    } label: {
                        Label("Playthrough", systemImage: playthroughFilter == nil
                              ? "line.3.horizontal.decrease.circle"
                              : "line.3.horizontal.decrease.circle.fill")
                            .foregroundStyle(LSTheme.accent)
                    }
                }
            }
        }
        .sheet(item: $editing) { EditSessionSheet(session: $0) }
    }

    private var summary: some View {
        HStack(spacing: 0) {
            stat("\(shown.count)", shown.count == 1 ? "session" : "sessions")
            Rectangle().fill(LSTheme.separator).frame(width: 1, height: 26)
            stat(Format.duration(shown.reduce(0) { $0 + $1.elapsed() }), "played")
            if let first = shown.last {
                Rectangle().fill(LSTheme.separator).frame(width: 1, height: 26)
                stat(first.startDate.formatted(.dateTime.month(.abbreviated).year()), "since")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: 13))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 9.5, weight: .medium))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func row(_ session: Session) -> some View {
        Button {
            // Same rule as the game page: a running or paused session is
            // edited by stopping it, not by typing over it.
            if session.state == .stopped { editing = session }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: session.isManual ? "square.and.pencil" : "stopwatch")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.startDate,
                         format: .dateTime.weekday(.abbreviated).month().day().hour().minute())
                        .font(.subheadline)
                    // The playthrough is named only when it could be ambiguous
                    // — with the filter on, or with one playthrough, it is
                    // noise on every row.
                    if playthroughFilter == nil, playthroughs.count > 1,
                       let name = session.playthrough?.name {
                        Text(name)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                if session.notes != nil {
                    Image(systemName: "note.text")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 8)
                Text(Format.duration(session.elapsed()))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                if session.state == .stopped {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// One month of sessions, newest first.
///
/// Pulled out of the view because grouping by month is arithmetic, not layout
/// — and arithmetic inside a `body` is arithmetic nobody can test. The month
/// boundary is the user's own calendar, so someone whose week starts on a
/// Sunday and someone whose year is Buddhist both get their own months.
struct SessionMonth: Identifiable {
    let start: Date
    let sessions: [Session]
    var id: Date { start }

    var total: TimeInterval { sessions.reduce(0) { $0 + $1.elapsed() } }

    static func group(_ sessions: [Session],
                      calendar: Calendar = .current) -> [SessionMonth] {
        Dictionary(grouping: sessions) { session in
            calendar.date(from: calendar.dateComponents([.year, .month],
                                                        from: session.startDate))
                ?? session.startDate
        }
        .map { SessionMonth(start: $0.key,
                            sessions: $0.value.sorted { $0.startDate > $1.startDate }) }
        .sorted { $0.start > $1.start }
    }
}
