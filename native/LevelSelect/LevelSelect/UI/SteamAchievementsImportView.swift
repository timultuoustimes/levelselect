import SwiftUI
import SwiftData

/// Pick which Steam game's achievements belong to this tracker, and install them.
///
/// Pushed, like `RetroAchievementsImportView`, and the choice is the user's
/// for the same reason: the wrong list is worse than none.
///
/// **No Steam connection needed** — the list comes through our proxy on
/// LevelSelect's key, as RetroAchievements' do. IGDB's own link to Steam comes
/// first, then Steam's store search; a connected account adds the player's own
/// library, which is the surest match of all.
struct SteamAchievementsImportView: View {
    let game: Game

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var loaded = false
    @State private var loading = false
    @State private var error: String?
    @State private var suggested: [Int] = []
    @State private var results: [SteamService.SearchResult] = []
    @State private var owned: [SteamService.OwnedGame] = []
    @State private var libraryNote: String?
    @State private var searchText = ""
    @State private var installing: Int?
    /// Finished items a refresh dropped, awaiting the keep-or-let-go call.
    @State private var lostProgress: [TrackerItemDTO] = []

    private var credentials: SteamCredentials.Value? { SteamCredentials.current }

    var body: some View {
        List {
            if loading {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Looking on Steam…").foregroundStyle(.secondary)
                }
            }
            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(LSTheme.working)
                    Button("Try Again") { Task { await load() } }
                }
            }

            if !suggested.isEmpty {
                Section("Matched by IGDB") {
                    ForEach(suggested, id: \.self) { appID in
                        row(appID: appID, name: name(for: appID), detail: libraryDetail(for: appID))
                    }
                }
            }

            if !yourGames.isEmpty {
                Section("In your Steam library") {
                    ForEach(yourGames) { owned in
                        row(appID: owned.appID, name: owned.name, detail: playtime(owned))
                    }
                }
            }

            Section {
                HStack {
                    TextField("Game name on Steam", text: $searchText)
                        .autocorrectionDisabled()
                        .onSubmit { Task { await runSearch() } }
                    Button("Go") { Task { await runSearch() } }
                        .disabled(searchText.trimmingCharacters(in: .whitespaces).count < 2)
                }
                ForEach(storeResults) { result in
                    row(appID: result.id, name: result.name, detail: libraryDetail(for: result.id))
                }
                if loaded && !loading && storeResults.isEmpty && suggested.isEmpty && yourGames.isEmpty {
                    Text("Nothing on Steam matched “\(searchText)”. Try part of the name.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Search Steam")
            } footer: {
                if credentials == nil {
                    Text("Connect Steam in Settings → Services to see your own library here and sync the achievements you've earned. The list itself needs nothing from you.")
                } else if let libraryNote {
                    Text(libraryNote)
                }
            }
        }
        .navigationTitle("Steam")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
            Text("Steam's list no longer has achievements you'd finished — \(names)\(more). Keep them as Personal Goals with their checkmarks, or let them go.")
        }
        .task {
            guard !loaded else { return }
            searchText = game.name
            await load()
        }
    }

    // MARK: Derived

    /// Your own games named like the search, minus IGDB's matches.
    private var yourGames: [SteamService.OwnedGame] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        return owned.filter { !suggested.contains($0.appID) && SteamService.namesMatch($0.name, query) }
    }

    /// Store results not already shown above.
    private var storeResults: [SteamService.SearchResult] {
        let shown = Set(suggested).union(yourGames.map(\.appID))
        return results.filter { !shown.contains($0.id) }
    }

    private func row(appID: Int, name: String, detail: String?) -> some View {
        Button {
            Task { await install(appID) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if installing == appID {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .disabled(installing != nil)
    }

    private func name(for appID: Int) -> String {
        owned.first { $0.appID == appID }?.name
            ?? results.first { $0.id == appID }?.name
            ?? "Steam app \(appID)"
    }

    /// Only said when there's a library to say it about.
    private func libraryDetail(for appID: Int) -> String? {
        guard !owned.isEmpty else { return nil }
        guard let game = owned.first(where: { $0.appID == appID }) else {
            return "Not in your Steam library"
        }
        return playtime(game) ?? "In your Steam library"
    }

    private func playtime(_ game: SteamService.OwnedGame) -> String? {
        guard game.minutesPlayed > 0 else { return nil }
        if game.minutesPlayed < 60 { return "\(game.minutesPlayed) minutes played" }
        let hours = Int(game.hoursPlayed.rounded())
        return "\(hours) hour\(hours == 1 ? "" : "s") played"
    }

    // MARK: Actions

    private func load() async {
        loading = true
        error = nil
        defer { loading = false; loaded = true }
        if let igdbID = game.igdbID {
            suggested = await SteamService.appIDs(forIGDB: igdbID)
        }
        do {
            results = try await SteamService.search(searchText)
        } catch {
            self.error = error.localizedDescription
        }
        // The library is a bonus, not a requirement: a private profile says so
        // quietly and the store search still works.
        if let credentials {
            do {
                owned = try await SteamService.ownedGames(credentials: credentials)
                libraryNote = nil
            } catch {
                libraryNote = error.localizedDescription
            }
        }
    }

    private func runSearch() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            results = try await SteamService.search(searchText)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func install(_ appID: Int) async {
        installing = appID
        defer { installing = nil }
        do {
            let installed = try await SteamService.achievements(appID: appID)
            let repo = Repository(context)
            repo.ensureDefaultPlaythrough(for: game)
            // Refresh in place when the list is already here, as the RA import
            // does: developers add and rename achievements after launch.
            let existing = repo.trackerCategories(for: game)
                .contains { $0.id == SteamService.categoryID }
            let outcome = repo.applyGeneratedSchema(
                for: game, jsonData: installed.schema,
                mode: existing ? .replaceCategories(ids: [SteamService.categoryID]) : .addAll,
                source: .imported, attribution: "steam")
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
