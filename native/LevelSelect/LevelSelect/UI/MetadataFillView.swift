import SwiftUI
import SwiftData

/// Settings → Your Data → "Fill in missing game info".
///
/// Shows what the library is missing, fills it from IGDB, and says what it
/// changed. Three things it is careful about, all of them for the same reason —
/// this runs over a library someone has been correcting by hand:
///
/// 1. Nothing is written over. Empty fields only, always.
/// 2. Games with no IGDB id are counted and left alone, never matched by
///    name. Guessing is what put "The Messenger" on a different game from 2000.
/// 3. The scan runs before anything is asked of the network, so the user reads
///    the number of games it will touch before agreeing to it.
struct MetadataFillView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Game> { $0.deletedAt == nil }, sort: \Game.name)
    private var games: [Game]

    @State private var running = false
    @State private var progress = 0.0
    @State private var result: Repository.MetadataFillResult?
    /// How many games the run set out to fetch. Snapshotted, because the live
    /// plan shrinks as games are filled and a label that counts itself down
    /// mid-run reads like the work is disappearing rather than being done.
    @State private var plannedCount = 0

    /// Recompute from the asked-and-answered cache each render, so a run's
    /// "nothing changed" outcomes take effect the moment the sheet reopens.
    private var plan: MetadataRefresh.Plan {
        MetadataRefresh.plan(for: games, checked: MetadataCheckedStore().all())
    }

    var body: some View {
        NavigationStack {
            Form {
                if let result {
                    resultSection(result)
                } else {
                    scanSection
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Missing Game Info")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(result == nil ? "Cancel" : "Done") { dismiss() }
                        .disabled(running)
                }
            }
            .interactiveDismissDisabled(running)
        }
    }

    private var emptyStateText: String {
        if plan.recentlyChecked > 0 {
            return "IGDB had nothing to add for what's still missing — checked within the last month."
        }
        return plan.unmatched.isEmpty
            ? "Every game has everything IGDB can tell us."
            : "Every game with an IGDB match is complete."
    }

    private var footerText: String {
        var parts = ["Counted across \(games.count) game\(games.count == 1 ? "" : "s"), \(plan.complete) of which already have everything."]
        if plan.informationalOnly > 0 {
            parts.append("\(plan.informationalOnly) only lack a series, which most games aren't in — they're not offered for lookup.")
        }
        if plan.recentlyChecked > 0 {
            parts.append("\(plan.recentlyChecked) were looked up in the last month and IGDB had nothing to add; they'll be asked again when that's stale.")
        }
        return parts.joined(separator: " ")
    }

    // MARK: Before

    @ViewBuilder
    private var scanSection: some View {
        let plan = self.plan

        Section {
            if plan.isEmpty {
                Label("Nothing to fill in", systemImage: "checkmark.circle")
                Text(emptyStateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(plan.reportableCounts, id: \.0) { field, count in
                    LabeledContent {
                        Text("\(count)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    } label: {
                        Text("Missing \(field.label)")
                    }
                }
                // Informational absences, phrased as facts: no series is the
                // normal condition for most games, not a gap to close.
                ForEach(plan.informationalCounts, id: \.0) { field, count in
                    LabeledContent {
                        Text("\(count)")
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                    } label: {
                        Text("No \(field.label) listed")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("What's missing")
        } footer: {
            Text(footerText)
        }

        if !plan.isEmpty {
            Section {
                if running {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: progress)
                        Text("Looking up \(plannedCount) game\(plannedCount == 1 ? "" : "s")…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button {
                        run()
                    } label: {
                        Label("Fill in \(plan.fillable.count) game\(plan.fillable.count == 1 ? "" : "s")",
                              systemImage: "sparkle.magnifyingglass")
                    }
                }
            } footer: {
                Text("Only empty fields are filled. Anything you've typed or corrected — platforms, ratings, notes, a name you changed — is left exactly as it is. Overwriting fetched fields wholesale needs per-field locks, which aren't built yet.")
            }
        }

        if !plan.unmatched.isEmpty {
            Section {
                ForEach(plan.unmatched.prefix(10)) { game in
                    Text(game.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if plan.unmatched.count > 10 {
                    Text("and \(plan.unmatched.count - 10) more")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } header: {
                Text("\(plan.unmatched.count) game\(plan.unmatched.count == 1 ? "" : "s") can't be looked up")
            } footer: {
                Text("These aren't linked to an IGDB entry, so there's nothing to fetch. Matching them by title would mean guessing between games that share a name, so it isn't done here — add the match from each game's page instead.")
            }
        }
    }

    // MARK: After

    /// Plain language for why lookups didn't come back. Deliberately says what
    /// to DO — "nothing was lost, try again in a minute" is the difference
    /// between waiting and tapping a dead button twenty more times.
    private func failureMessage(_ failure: IGDBError) -> (String, String, String) {
        switch failure {
        case .rateLimited:
            ("Hit the lookup limit", "exclamationmark.triangle",
             "Game lookups are capped at 60 a minute, and this run used them up — repeated runs share the same allowance. Nothing was lost and nothing was half-written. Wait a minute and run it again.")
        case .offline:
            ("No connection", "wifi.slash",
             "The lookups couldn't reach the network. Nothing was changed. Try again once you're back online.")
        case .unavailable:
            ("Lookups are switched off", "exclamationmark.triangle",
             "The lookup service is temporarily unavailable. Nothing was changed. Try again later.")
        case .rejected(let status):
            ("Lookups were refused (\(status))", "exclamationmark.triangle",
             "The lookup service turned the request down. Nothing was changed.")
        case .malformed:
            ("Couldn't read the reply", "exclamationmark.triangle",
             "A batch came back in a shape the app couldn't read. Nothing was changed.")
        }
    }

    @ViewBuilder
    private func resultSection(_ result: Repository.MetadataFillResult) -> some View {
        // A run that fetched nothing leads with WHY. Burying that under
        // "Nothing changed" reads as "IGDB had nothing for you", which sends
        // someone off to re-check their library instead of waiting a minute.
        if let failure = result.failure, !result.didAnything {
            Section {
                let (title, icon, detail) = failureMessage(failure)
                Label(title, systemImage: icon)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Couldn't fetch")
            }
        }

        Section {
            if result.didAnything {
                Label("Updated \(result.gamesUpdated) game\(result.gamesUpdated == 1 ? "" : "s")",
                      systemImage: "checkmark.circle")
                LabeledContent("Fields filled") {
                    Text("\(result.fieldsFilled)").monospacedDigit()
                }
                if result.releaseDatesFixed > 0 {
                    LabeledContent("Release dates fixed") {
                        Text("\(result.releaseDatesFixed)").monospacedDigit()
                    }
                }
            } else {
                Label("Nothing changed", systemImage: "minus.circle")
                Text("IGDB had nothing to add to the \(result.gamesAttempted) game\(result.gamesAttempted == 1 ? "" : "s") looked up.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Done")
        }

        if result.unknownToIGDB > 0 || result.chunksFailed > 0
            || result.deferred > 0 || result.unmatched > 0 {
            Section {
                if result.unknownToIGDB > 0 {
                    Text("\(result.unknownToIGDB) game\(result.unknownToIGDB == 1 ? "" : "s") had an IGDB link that no longer resolves. Those need a new match rather than a refresh.")
                }
                if result.chunksFailed > 0 {
                    Text("\(result.chunksFailed) batch\(result.chunksFailed == 1 ? "" : "es") couldn't be fetched\(result.failure.map { " — \(failureMessage($0).0.lowercased())" } ?? ""). Nothing was lost; those games stay in the list and a later run picks them up.")
                }
                if result.deferred > 0 {
                    Text("\(result.deferred) game\(result.deferred == 1 ? "" : "s") were left for a second run, to stay inside the lookup limit. Run it again to pick them up.")
                }
                if result.unmatched > 0 {
                    Text("\(result.unmatched) game\(result.unmatched == 1 ? "" : "s") aren't linked to IGDB at all, so nothing could be fetched for them.")
                }
            } header: {
                Text("Still outstanding")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func run() {
        running = true
        progress = 0
        plannedCount = plan.fillable.count
        Task { @MainActor in
            let repo = Repository(context)
            let outcome = await repo.fillMissingMetadata(in: games) { value in
                progress = value
            }
            result = outcome
            running = false
        }
    }
}
