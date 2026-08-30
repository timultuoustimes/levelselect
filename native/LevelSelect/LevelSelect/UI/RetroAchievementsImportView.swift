import SwiftUI
import SwiftData

/// Pick which RetroAchievements set belongs to this game, and install it.
///
/// Pushed rather than presented. The tracker section already carries three
/// `.sheet` modifiers, and this app has twice shipped a bug where sheets
/// swallowed each other — a list of candidates is also simply better with a
/// full screen and a back button.
///
/// The choice is the user's on purpose. RA titles carry regional variants
/// ("Castlevania | Akumajou Dracula"), subsets and ROM hacks, so picking
/// automatically would sometimes install a confidently wrong achievement set —
/// and the wrong 30 items are much worse than none.
struct RetroAchievementsImportView: View {
    let game: Game

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    /// Finished items the refresh dropped, awaiting the keep-or-let-go call.
    @State private var lostProgress: [TrackerItemDTO] = []

    @State private var loading = true
    @State private var error: String?
    @State private var consoleName: String?
    @State private var matches: [RetroAchievementsService.Match] = []
    @State private var consoles: [RetroAchievementsService.Console] = []
    @State private var chosenConsole: Int?
    @State private var installing: Int?
    @State private var manualName = ""

    var body: some View {
        List {
            if loading {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Looking on RetroAchievements…").foregroundStyle(.secondary)
                }
            } else if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(LSTheme.working)
                    Button("Try Again") { Task { await load() } }
                }
            }

            if !consoles.isEmpty {
                Section("Which system?") {
                    Text("RetroAchievements doesn't recognize \(PlatformPreference.owned(game.platforms) ?? "this platform"). Pick the system this copy runs on.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(consoles) { console in
                        Button(console.name) {
                            chosenConsole = console.id
                            consoles = []
                            Task { await load() }
                        }
                    }
                }
            }

            if !matches.isEmpty {
                Section(consoleName.map { "On \($0)" } ?? "Matches") {
                    ForEach(matches) { match in
                        Button {
                            Task { await install(match) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(match.title)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                    Text("\(match.achievements) achievement\(match.achievements == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                if installing == match.id {
                                    ProgressView().controlSize(.small)
                                }
                            }
                        }
                        .disabled(installing != nil)
                    }
                }
            } else if !loading && error == nil && consoles.isEmpty {
                Section {
                    Text("Nothing on RetroAchievements matched “\(game.name)”. It may be listed under a different name — try searching for part of it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // RA's titles don't always match a library's. Searching by hand is
            // the way out of that, rather than a dead end.
            Section("Search by name") {
                HStack {
                    TextField("Game name on RetroAchievements", text: $manualName)
                        .onSubmit { Task { await load(name: manualName) } }
                    Button("Go") { Task { await load(name: manualName) } }
                        .disabled(manualName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .navigationTitle("RetroAchievements")
        .confirmationDialog(
            "\(lostProgress.count) finished item\(lostProgress.count == 1 ? "" : "s") dropped",
            isPresented: Binding(get: { !lostProgress.isEmpty },
                                 set: { if !$0 { lostProgress = [] } }),
            titleVisibility: .visible
        ) {
            Button("Keep as Personal Goals") {
                Repository(context).rescueAsPersonalGoals(lostProgress, for: game)
                lostProgress = []
                dismiss()
            }
            Button("Let Them Go", role: .destructive) {
                lostProgress = []
                dismiss()
            }
        } message: {
            let names = lostProgress.prefix(3).map(\.name).joined(separator: ", ")
            let more = lostProgress.count > 3 ? " and \(lostProgress.count - 3) more" : ""
            Text("RetroAchievements retired or revised achievements you'd finished — \(names)\(more). Keep them as Personal Goals with their checkmarks, or let them go.")
        }
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { if matches.isEmpty { await load() } }
    }

    private func load(name: String? = nil) async {
        let query = (name?.trimmingCharacters(in: .whitespaces)).flatMap { $0.isEmpty ? nil : $0 }
            ?? game.name
        loading = true
        error = nil
        do {
            let result = try await RetroAchievementsService.search(
                gameName: query,
                platform: PlatformPreference.owned(game.platforms),
                consoleID: chosenConsole)
            switch result {
            case .needsConsole(let list):
                consoles = list
                matches = []
            case .matches(let console, let results):
                consoleName = console.name
                chosenConsole = console.id
                matches = results
                consoles = []
            }
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func install(_ match: RetroAchievementsService.Match) async {
        installing = match.id
        defer { installing = nil }
        do {
            let installed = try await RetroAchievementsService.achievements(gameID: match.id)
            let repo = Repository(context)
            repo.ensureDefaultPlaythrough(for: game)
            // Refresh in place when the set is already here — RA adds and
            // revises achievements, and appending would leave the retired ones
            // sitting in the list forever. First time, it's a plain install.
            let existing = repo.trackerCategories(for: game)
                .contains { $0.id == "retroachievements" }
            let outcome = repo.applyGeneratedSchema(
                for: game, jsonData: installed.schema,
                mode: existing ? .replaceCategories(ids: ["retroachievements"]) : .addAll,
                source: .imported, attribution: "retroachievements")
            // A refresh replaces the category, and RA does retire and revise
            // achievements — anything you'd FINISHED that fell out must be
            // offered back, not silently discarded with the dismiss. Same
            // rescue the regeneration path has had; this view just never
            // looked at the outcome it was handed.
            if outcome.lostProgress.isEmpty {
                dismiss()
            } else {
                lostProgress = outcome.lostProgress
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
