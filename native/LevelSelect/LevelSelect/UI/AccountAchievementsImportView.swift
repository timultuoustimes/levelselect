import SwiftUI
import SwiftData

/// Pick which PlayStation or Xbox game's list belongs to this tracker.
///
/// Both services only share lists with a signed-in account, so the candidates
/// are the player's own games — narrowed to names like this game's, and
/// searchable. The choice is theirs for the same reason as the RA and Steam
/// imports: the wrong list is worse than none.
struct AccountAchievementsImportView: View {
    enum Source: String, Hashable, Identifiable {
        case playStation, xbox
        var id: String { rawValue }
        var name: String { self == .playStation ? "PlayStation" : "Xbox" }
        var noun: String { self == .playStation ? "trophies" : "achievements" }
        /// The same ids as `PlayStationService.categoryID` and `XboxService.categoryID`,
        /// spelled here because those are main-actor state and this enum isn't.
        var categoryID: String { self == .playStation ? "playstation" : "xbox" }
        @MainActor var isConnected: Bool {
            self == .playStation ? PlayStationCredentials.isConfigured : XboxCredentials.isConfigured
        }
    }

    struct Candidate: Identifiable, Equatable {
        let id: String
        let name: String
        let detail: String
    }

    let game: Game
    let source: Source

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var loaded = false
    @State private var loading = false
    @State private var error: String?
    @State private var candidates: [Candidate] = []
    @State private var playStationTitles: [String: PlayStationService.TrophyTitle] = [:]
    @State private var xboxTitles: [String: XboxService.Title] = [:]
    @State private var search = ""
    @State private var installing: String?
    @State private var lostProgress: [TrackerItemDTO] = []

    var body: some View {
        List {
            if !source.isConnected {
                Section {
                    Label("Connect \(source.name) first, in Settings → Services. \(source.name) only shares \(source.noun) with a signed-in account.",
                          systemImage: "person.crop.circle.badge.questionmark")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                if loading {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Looking on \(source.name)…").foregroundStyle(.secondary)
                    }
                }
                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(LSTheme.working)
                        Button("Try Again") { Task { await load() } }
                    }
                }
                if loaded {
                    Section("Your \(source.name) games") {
                        TextField("Search your \(source.name) games", text: $search)
                            .autocorrectionDisabled()
                        ForEach(filtered) { candidate in
                            Button {
                                Task { await install(candidate) }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(candidate.name)
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                        Text(candidate.detail)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 8)
                                    if installing == candidate.id { ProgressView().controlSize(.small) }
                                }
                            }
                            .disabled(installing != nil)
                        }
                        if filtered.isEmpty {
                            Text(search.isEmpty
                                 ? "Nothing in your \(source.name) games is named like “\(game.name)”. Search for part of the name."
                                 : "None of your \(source.name) games match “\(search)”.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(source.name)
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
            Text("\(source.name)'s list no longer has \(source.noun) you'd finished — \(names)\(more). Keep them as Personal Goals with their checkmarks, or let them go.")
        }
        .task {
            guard !loaded, source.isConnected else { return }
            await load()
        }
    }

    private var filtered: [Candidate] {
        let query = search.trimmingCharacters(in: .whitespaces)
        if query.isEmpty { return candidates.filter { SteamService.namesMatch($0.name, game.name) } }
        return candidates.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private func load() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            switch source {
            case .playStation:
                let titles = try await PlayStationService.trophyTitles()
                playStationTitles = Dictionary(titles.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                candidates = titles.map {
                    Candidate(id: $0.id, name: $0.name,
                              detail: "\($0.platform.isEmpty ? "" : "\($0.platform) · ")\($0.earned) of \($0.defined) trophies")
                }
            case .xbox:
                let titles = try await XboxService.titles().filter { $0.total > 0 }
                xboxTitles = Dictionary(titles.map { (String($0.id), $0) }, uniquingKeysWith: { a, _ in a })
                candidates = titles.map {
                    Candidate(id: String($0.id), name: $0.name,
                              detail: "\($0.earned) of \($0.total) achievements")
                }
            }
            loaded = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func install(_ candidate: Candidate) async {
        installing = candidate.id
        defer { installing = nil }
        do {
            let set: ImportedSet
            switch source {
            case .playStation:
                guard let title = playStationTitles[candidate.id] else { return }
                set = try await PlayStationService.trophyList(for: title)
            case .xbox:
                guard let title = xboxTitles[candidate.id] else { return }
                set = try await XboxService.achievements(titleID: title.id, titleName: title.name).set
            }
            let repo = Repository(context)
            repo.ensureDefaultPlaythrough(for: game)
            let existing = repo.trackerCategories(for: game).contains { $0.id == source.categoryID }
            let outcome = repo.applyGeneratedSchema(
                for: game, jsonData: set.schema,
                mode: existing ? .replaceCategories(ids: [source.categoryID]) : .addAll,
                source: .imported, attribution: source == .playStation ? "playstation" : "xbox")
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
