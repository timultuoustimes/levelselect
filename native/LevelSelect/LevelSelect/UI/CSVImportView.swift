import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Import a library from a CSV file, in three steps: pick a file, review what
/// was understood, then match each row against IGDB before anything is saved.
///
/// The match-review step is the important one and the reason this is a screen
/// rather than a button. Titles in other people's exports rarely match IGDB
/// exactly — editions, subtitles, regional names — so importing blind either
/// creates duplicates or silently attaches the wrong cover art. Every row
/// resolves to confirmed / needs-review / skipped, and nothing is written
/// until the user says go.
///
/// It's also the piece Steam, RetroAchievements, and itch.io will reuse when
/// those arrive; only the row-producing half differs.
struct CSVImportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var stage: Stage = .pick
    @State private var parse: CSVImport.ParseResult?
    @State private var candidates: [Candidate] = []
    @State private var matching = false
    @State private var matchProgress = 0.0
    @State private var importError: String?
    /// What to send when a file can't be read — see `ImportReportButton`.
    @State private var failedImport: ImportFailureReport?
    @State private var imported: CSVImport.Applied?
    @State private var showingPicker = false
    @State private var sync = SyncStatusMonitor.shared
    /// Consoles you have a record for, to start rows on and to offer.
    @State private var owned: Set<String> = []
    /// What a game you already have is recorded on today, so a row can say
    /// what it's adding TO. Tim, 09-17: *"I'm not sure if that means they all
    /// already are labeled as Mac games or if they're unlabeled."*
    @State private var existingPlatforms: [UUID: [String]] = [:]
    /// Shown under the progress bar while IGDB asks us to slow down.
    @State private var matchStatus: String?
    /// The row being searched by hand.
    @State private var searching: Candidate.ID?
    /// When this sheet's IGDB requests went out, for pacing.
    @State private var sent: [Date] = []

    private enum Stage { case pick, review, done }

    /// Rows another importer already produced (Steam's library), which skip
    /// the file picker and go straight to matching and review. The review is
    /// the part worth sharing; only where the rows come from differs.
    private let preloaded: [CSVImport.Row]?
    private let title: String
    private let sourceLabel: String

    init() {
        preloaded = nil
        title = "Import from CSV"
        sourceLabel = "CSV"
    }

    init(rows: [CSVImport.Row], title: String, sourceLabel: String) {
        preloaded = rows
        self.title = title
        self.sourceLabel = sourceLabel
    }

    /// One CSV row plus whatever IGDB thinks it is.
    /// Not private: CandidateRow below takes a Binding to it.
    struct Candidate: Identifiable {
        let id = UUID()
        var row: CSVImport.Row
        var match: IGDBGame?
        var alternatives: [IGDBGame] = []
        var include = true
        /// True when the title didn't match exactly — worth a human glance.
        var uncertain = false
        /// The consoles the row's menu offers. Follows the match, which can
        /// add one: see `CSVImport.platformChoices`.
        var platformChoices: [String] = []
        /// Once you pick consoles, a new match keeps them.
        var platformsPicked = false
        /// IGDB couldn't be asked, as opposed to having no answer.
        var lookupFailed = false

        mutating func refreshPlatforms(owned: Set<String>) {
            guard row.offersPlatformChoice else { return }
            platformChoices = CSVImport.platformChoices(
                for: row, matchPlatforms: match?.platforms ?? [], owned: owned)
            let kept = row.platforms.filter(platformChoices.contains)
            if row.platformsKnown, !platformsPicked { return }
            if platformsPicked, !kept.isEmpty {
                row.platforms = kept
                row.platform = kept.first
            } else {
                row = CSVImport.preferOwnedPlatform(row, choices: platformChoices, owned: owned)
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .pick:   pickStage
                case .review: reviewStage
                case .done:   doneStage
                }
            }
            .lsBackground()
            .navigationTitle(title)
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(stage == .done ? "Done" : "Cancel") { dismiss() }
                }
                if stage == .review {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Import \(includedCount)") { runImport() }
                            .disabled(includedCount == 0 || matching || sync.isImporting)
                    }
                }
            }
            .sheet(item: Binding(
                get: { searching.flatMap { id in candidates.first { $0.id == id } }.map(SearchTarget.init) },
                set: { searching = $0?.id })) { target in
                ImportSearchSheet(target: target) { game, results in
                    guard let index = candidates.firstIndex(where: { $0.id == target.id }) else { return }
                    candidates[index].match = game
                    if !results.isEmpty { candidates[index].alternatives = results }
                    candidates[index].uncertain = false
                    candidates[index].lookupFailed = false
                    candidates[index].refreshPlatforms(owned: owned)
                }
            }
            .fileImporter(isPresented: $showingPicker,
                          allowedContentTypes: [.commaSeparatedText, .plainText, .text]) { result in
                handleFile(result)
            }
            .task {
                guard let preloaded, parse == nil else { return }
                parse = CSVImport.ParseResult(rows: preloaded, recognizedColumns: [],
                                              ignoredColumns: [], skippedLines: [])
                owned = Set(Repository(context).liveConsoles().map(\.platform))
                existingPlatforms = Self.platformsOfExisting(in: context)
                candidates = preloaded.map { row in
                    var candidate = Candidate(row: row, include: row.skipReason == nil)
                    candidate.refreshPlatforms(owned: owned)
                    return candidate
                }
                stage = .review
                await matchAll()
            }
        }
    }

    // MARK: Stage 1 — pick

    private var pickStage: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "tablecells")
                    .font(.system(size: 44))
                    .foregroundStyle(LSTheme.accent)
                    .padding(.top, 30)

                Text("Bring your library over")
                    .font(.title3.bold())

                Text("Export a CSV from Gamery, Backloggd, a spreadsheet, or anywhere else, then pick it here. Nothing is added until you've reviewed the matches.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button {
                    showingPicker = true
                } label: {
                    Label("Choose a CSV file", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 6) {
                    Text("WHAT IT READS")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .kerning(0.8)
                    Text("A title column is required. Platform, status, rating, hours, and notes are used when present — column names can vary (Title/Game/Name, Shelf/List/Status, Score/Stars/Rating). Anything else is ignored.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .lsCard()
                .padding(.horizontal)

                if let importError {
                    Text(importError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                    if let failedImport {
                        ImportReportButton(report: failedImport)
                            .padding(.horizontal)
                    }
                }
            }
        }
    }

    // MARK: Stage 2 — review

    private var reviewStage: some View {
        List {
            if let parse {
                Section {
                    LabeledContent("Rows found", value: "\(parse.rows.count)")
                    if !parse.recognizedColumns.isEmpty {
                        LabeledContent("Columns used",
                                       value: parse.recognizedColumns.joined(separator: ", "))
                        .font(.subheadline)
                    }
                    if !parse.ignoredColumns.isEmpty {
                        LabeledContent("Ignored",
                                       value: parse.ignoredColumns.joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    if !parse.skippedLines.isEmpty {
                        Label("\(parse.skippedLines.count) row(s) had no title and were skipped",
                              systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                } header: {
                    Text("What we read")
                }
            }

            if matching {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: matchProgress)
                        Text(matchStatus ?? "Looking up games…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if sync.isImporting {
                Section {
                    Label("Waiting for iCloud to finish bringing your library in. Importing now could add games it's about to restore a second time.",
                          systemImage: "icloud.and.arrow.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            if uncertainCount > 0 {
                Section {
                    Label("\(uncertainCount) title(s) didn't match exactly — check these before importing.",
                          systemImage: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }

            Section {
                ForEach($candidates) { $candidate in
                    CandidateRow(candidate: $candidate, owned: owned,
                                 already: candidate.row.existingGameID.flatMap { existingPlatforms[$0] } ?? []) {
                        searching = candidate.id
                    }
                }
            } header: {
                HStack {
                    Text("Games")
                    Spacer()
                    let bulk = CSVImport.bulkPlatforms(candidates.map(\.platformChoices))
                    if !bulk.isEmpty {
                        Menu("Console for all") {
                            ForEach(bulk, id: \.platform) { option in
                                Button("\(PlatformShort.name(option.platform)) (\(option.rows))") {
                                    setAll(to: option.platform)
                                }
                            }
                        }
                        .font(.caption)
                        .textCase(nil)
                        .fixedSize()
                    }
                    Button(includedCount == candidates.count ? "Deselect all" : "Select all") {
                        let target = includedCount != candidates.count
                        for index in candidates.indices { candidates[index].include = target }
                    }
                    .font(.caption)
                    .textCase(nil)
                }
            }
        }
        #if os(macOS)
        .listStyle(.inset)
        #else
        .listStyle(.insetGrouped)
        #endif
        .scrollContentBackground(.hidden)
    }

    // MARK: Stage 3 — done

    private var doneStage: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("Imported \(imported?.added ?? 0) games")
                .font(.title3.bold())
            if let updated = imported?.updated, updated > 0 {
                Text("Added a console to \(updated) you already had.")
                    .font(.subheadline)
            }
            Text("Trackers for games we ship built-in ones for have been attached automatically.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Derived

    private var includedCount: Int { candidates.filter(\.include).count }
    private var uncertainCount: Int { candidates.filter { $0.uncertain && $0.include }.count }

    // MARK: Actions

    private func handleFile(_ result: Result<URL, Error>) {
        importError = nil
        failedImport = nil
        do {
            let url = try result.get()
            // Files chosen outside the sandbox need explicit access.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            let data = try Data(contentsOf: url)
            // Exports are usually UTF-8 but Windows tools still emit Latin-1.
            let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
                ?? ""
            guard !text.isEmpty else {
                importError = "That file appears to be empty."
                return
            }
            let parsed = CSVImport.parse(text)
            guard !parsed.rows.isEmpty else {
                importError = "No rows with a title were found. The file needs a column named Title, Name, or Game."
                failedImport = ImportFailureReport(source: "CSV file", problem: importError ?? "",
                                            fileName: url.lastPathComponent, content: text)
                return
            }
            parse = parsed
            candidates = parsed.rows.map { Candidate(row: $0) }
            stage = .review
            Task { await matchAll() }
        } catch {
            importError = "Couldn't read that file. \(error.localizedDescription)"
        }
    }

    /// Resolve every row against IGDB, marking anything that isn't an exact
    /// title match so the user can look before it's saved.
    ///
    /// **A row that carries an IGDB id is matched by it**, fifty to a request,
    /// and is never flagged: the id is the game. Tim's Gamery export has one
    /// on every row and the importer ignored the column, so 65 of 140 came
    /// back "didn't match exactly" and had to be checked by hand.
    private func matchAll() async {
        matching = true
        matchProgress = 0
        let ids = candidates.compactMap(\.row.igdbID)
        var byID: [Int: IGDBGame] = [:]
        for start in stride(from: 0, to: ids.count, by: 50) {
            let chunk = Array(ids[start..<min(start + 50, ids.count)])
            for game in await patiently({ try await IGDBService.lookup(ids: chunk) }) ?? [] {
                byID[game.id] = game
            }
        }
        let library = CSVImport.LibraryKeys(
            (try? context.fetch(FetchDescriptor<Game>(predicate: #Predicate { $0.deletedAt == nil }))) ?? [])
        for index in candidates.indices {
            if candidates[index].row.existingGameID != nil {
                // Already matched, when it was added.
            } else if let id = candidates[index].row.igdbID, let game = byID[id] {
                candidates[index].match = game
                candidates[index].uncertain = false
                candidates[index].row.existingGameID = library.byIGDB[game.id]
            } else {
                let name = candidates[index].row.name
                let found = await patiently { try await IGDBService.search(name: CSVImport.searchName(name)) }
                candidates[index].lookupFailed = (found == nil)
                let hits = found ?? []
                let hints = CSVImport.matchHints(for: candidates[index].row)
                let best = CSVImport.bestMatch(hits, name: name, hints: hints)
                let exact = best.exact ? best.game : nil
                let exactOnly = candidates[index].row.exactMatchOnly
                candidates[index].match = exactOnly ? exact : best.game
                candidates[index].alternatives = CSVImport.ranked(hits, hints: hints)
                // A store full of games IGDB doesn't know: no exact match is
                // the expected answer, not a question.
                candidates[index].uncertain = !best.exact && !exactOnly
                // The game is already in your library under another name:
                // IGDB says which, so the row adds a console to it instead.
                if let exact, let mine = library.byIGDB[exact.id] {
                    candidates[index].row.existingGameID = mine
                }
                if candidates[index].row.mayBeAnApp, exact == nil, found != nil {
                    candidates[index].include = false
                    candidates[index].row.skipReason = "May be an app — left unticked"
                }
            }
            candidates[index].refreshPlatforms(owned: owned)
            matchProgress = Double(index + 1) / Double(candidates.count)
        }
        // Rows that turned out to be games you have, on consoles you already
        // own them on, have nothing to add.
        let worth = Set(CSVImport.dropNothingToAdd(candidates.map(\.row), context: context).map(\.id))
        candidates.removeAll { !worth.contains($0.row.id) }
        matching = false
    }

    /// One IGDB request, waiting out the proxy's per-minute limit (60) rather
    /// than reading it as "no match". An import of 80 rows asks faster than
    /// that, and every row past the limit came back with nothing to choose
    /// from. Nil when IGDB still can't be asked.
    private func patiently<T>(_ request: () async throws -> T) async -> T? {
        for attempt in 0..<5 {
            let wait = CSVImport.paceDelay(now: .now, recent: sent)
            if wait > 0 {
                matchStatus = "Pacing lookups to IGDB's limit — a moment…"
                try? await Task.sleep(for: .seconds(wait))
            }
            sent = sent.filter { Date.now.timeIntervalSince($0) < 60 } + [.now]
            do {
                let value = try await request()
                matchStatus = nil
                return value
            } catch IGDBError.rateLimited where attempt < 4 {
                matchStatus = "IGDB asked us to slow down — waiting a moment…"
                try? await Task.sleep(for: .seconds(15))
            } catch {
                matchStatus = nil
                return nil
            }
        }
        return nil
    }

    /// Every row that offers `platform` lands on it alone.
    private func setAll(to platform: String) {
        let key = PlatformKey.canonical(platform)
        for index in candidates.indices {
            guard let option = candidates[index].platformChoices.first(where: {
                PlatformKey.canonical($0) == key
            }), candidates[index].platformChoices.count > 1 else { continue }
            candidates[index].row.choosePlatform(option)
            candidates[index].platformsPicked = true
        }
    }

    private func runImport() {
        imported = CSVImport.apply(
            candidates.filter(\.include).map { ($0.row, $0.match) },
            context: context, sourceLabel: sourceLabel)
        stage = .done
    }
}

extension CSVImportView {
    /// Every live game's consoles, by id.
    @MainActor
    static func platformsOfExisting(in context: ModelContext) -> [UUID: [String]] {
        let games = (try? context.fetch(
            FetchDescriptor<Game>(predicate: #Predicate { $0.deletedAt == nil }))) ?? []
        var out: [UUID: [String]] = [:]
        for game in games where !game.ownedPlatformNames.isEmpty {
            out[game.id] = game.ownedPlatformNames
        }
        return out
    }
}

/// One reviewable row: what the CSV said, what IGDB found, and a way to change it.
private struct CandidateRow: View {
    @Binding var candidate: CSVImportView.Candidate
    let owned: Set<String>
    /// The consoles this game is already recorded on, when it's one you have.
    var already: [String] = []
    let search: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                candidate.include.toggle()
            } label: {
                Image(systemName: candidate.include ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(candidate.include ? LSTheme.accent : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.match?.name ?? candidate.row.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if candidate.lookupFailed {
                        Label("couldn't look up", systemImage: "wifi.exclamationmark")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    } else if candidate.uncertain {
                        Label("check", systemImage: "questionmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    if candidate.row.existingGameID != nil {
                        // Which consoles it has now, not only that it's here:
                        // "adds PC" to a game already on Mac and "adds PC" to
                        // a game on nothing are different facts.
                        Text(already.isEmpty
                             ? "In your library, no console yet — adds"
                             : "In your library on \(already.map(PlatformShort.name).joined(separator: ", ")) — adds")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let reason = candidate.row.skipReason {
                        Text(reason)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    // Show the original when IGDB renamed it, so a wrong match
                    // is obvious rather than hidden behind a tidy title.
                    if let match = candidate.match, !CSVImport.sameTitle(match.name, candidate.row.name) {
                        Text("was “\(candidate.row.name)”")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let match = candidate.match,
                       let when = ImportGameText.release(match, on: CSVImport.matchHints(for: candidate.row)) {
                        Text(when).font(.caption2).foregroundStyle(.secondary)
                    }
                    if candidate.platformChoices.count > 1 {
                        platformMenu
                    } else if let platform = candidate.row.platform {
                        // The app's short name: a Steam import's rows carried
                        // IGDB's "PC (Microsoft Windows)" and wrapped.
                        Text(PlatformShort.name(platform)).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer(minLength: 4)

            if candidate.row.existingGameID == nil {
                // A sheet, not a menu: telling two games with nearly one name
                // apart takes the box and the year, which a menu can't show.
                Button(action: search) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Change match")
            }
        }
        .listRowBackground(Color.clear)
    }

    /// The consoles, as a menu you can tick several in.
    private var platformMenu: some View {
        Menu {
            ForEach(candidate.platformChoices, id: \.self) { option in
                Toggle(PlatformShort.name(option), isOn: Binding(
                    get: { candidate.row.platforms.contains(option) },
                    set: { _ in
                        candidate.row.togglePlatform(option, order: candidate.platformChoices)
                        candidate.platformsPicked = true
                    }))
            }
        } label: {
            HStack(spacing: 2) {
                Text(candidate.row.platforms.isEmpty ? "Console"
                     : candidate.row.platforms.map(PlatformShort.name).joined(separator: ", "))
                Image(systemName: "chevron.up.chevron.down").imageScale(.small)
            }
            .font(.caption2)
            .foregroundStyle(LSTheme.accent)
        }
        .font(.caption2)
        .controlSize(.mini)
        #if os(macOS)
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        #endif
        .accessibilityLabel("Console")
    }
}

/// The row a picker sheet is for.
private struct SearchTarget: Identifiable {
    let id: UUID
    let name: String
    let hints: [String]
    let alternatives: [IGDBGame]
    let currentID: Int?
    init(_ candidate: CSVImportView.Candidate) {
        id = candidate.id
        name = candidate.row.name
        hints = CSVImport.matchHints(for: candidate.row)
        alternatives = candidate.alternatives
        currentID = candidate.match?.id
    }
}

/// How a candidate game is told apart from its namesakes.
enum ImportGameText {
    /// The day it came out on the row's console when IGDB has it, else its
    /// first release — the day when known, the year otherwise.
    static func release(_ game: IGDBGame, on hints: [String]) -> String? {
        let keys = Set(hints.map(PlatformKey.canonical))
        if let onConsole = game.platformReleases
            .filter({ keys.contains(PlatformKey.canonical($0.platform)) && $0.precision.hasDay })
            .min(by: { $0.timestamp < $1.timestamp }) {
            return Date(timeIntervalSince1970: onConsole.timestamp)
                .formatted(date: .abbreviated, time: .omitted)
        }
        if game.releasePrecision.hasDay, let date = game.releaseDate {
            return date.formatted(date: .abbreviated, time: .omitted)
        }
        return game.releaseYear.map(String.init)
    }

    /// Its consoles, the row's own first.
    static func platforms(_ game: IGDBGame, hints: [String]) -> [String] {
        let keys = Set(hints.map(PlatformKey.canonical))
        let sorted = PlatformPreference.sorted(game.platforms)
        var seen = Set<String>()
        return (sorted.filter { keys.contains(PlatformKey.canonical($0)) }
                + sorted.filter { !keys.contains(PlatformKey.canonical($0)) })
            .map(PlatformShort.name)
            .filter { seen.insert($0).inserted }
    }
}

/// Choose which game a row is: what its title found, or a search of your own.
/// Each game shows its box, its release date on your console, and what else
/// it's on — "Modern Warfare 3" (2011, 360) and "Modern Warfare III" (2023,
/// Series) differ by a numeral and nothing else in a list of names. Press and
/// hold a game for its box at full size.
private struct ImportSearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    let target: SearchTarget
    let pick: (IGDBGame?, [IGDBGame]) -> Void
    @State private var name = ""
    @State private var results: [IGDBGame] = []
    @State private var loading = false
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Title", text: $name)
                        .onSubmit { Task { await run() } }
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                } footer: {
                    Text("Press and hold a game to see its box.")
                }
                if loading {
                    ProgressView()
                } else if let failure {
                    Text(failure).font(.caption).foregroundStyle(.orange)
                }
                Section {
                    ForEach(results, id: \.id) { game in
                        row(game)
                    }
                }
                Section {
                    Button("Keep “\(target.name)” as typed") {
                        pick(nil, results)
                        dismiss()
                    }
                } footer: {
                    Text("Adds it without IGDB's details or box art.")
                }
            }
            .navigationTitle("Which game?")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Search") { Task { await run() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).count < 2 || loading)
                }
            }
            .onAppear {
                name = target.name
                results = target.alternatives
            }
            // What the import already found is the first answer; only a row
            // with nothing to show asks IGDB again on open.
            .task { if target.alternatives.isEmpty { await run() } }
        }
    }

    private func row(_ game: IGDBGame) -> some View {
        Button {
            pick(game, results)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                CoverThumb(urlString: game.coverURLString)
                    .frame(width: 44, height: 59)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                VStack(alignment: .leading, spacing: 3) {
                    Text(game.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text([ImportGameText.release(game, on: target.hints), game.typeLabel]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    platformLine(game)
                }
                Spacer(minLength: 4)
                if game.id == target.currentID {
                    Image(systemName: "checkmark").foregroundStyle(LSTheme.accent)
                }
            }
        }
        .contextMenu {
            Button("Use This Game", systemImage: "checkmark") {
                pick(game, results)
                dismiss()
            }
        } preview: {
            VStack(spacing: 10) {
                CoverThumb(urlString: game.coverURLString)
                    .frame(width: 240, height: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Text(game.name).font(.headline).multilineTextAlignment(.center)
                if let when = ImportGameText.release(game, on: target.hints) {
                    Text(when).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(width: 280)
        }
    }

    /// The row's console in the accent when the game is on it.
    private func platformLine(_ game: IGDBGame) -> some View {
        let names = ImportGameText.platforms(game, hints: target.hints)
        let onConsole = CSVImport.isOn(game, target.hints)
        let first = names.first.map { Text($0).foregroundStyle(onConsole ? LSTheme.accent : .secondary) }
            ?? Text("")
        let rest = names.dropFirst().prefix(3)
        return (rest.isEmpty ? first : first + Text(" · " + rest.joined(separator: " · ")).foregroundStyle(.secondary))
            .font(.caption2)
            .lineLimit(1)
    }

    private func run() async {
        loading = true
        failure = nil
        defer { loading = false }
        do {
            results = CSVImport.ranked(
                try await IGDBService.search(name: CSVImport.searchName(name)), hints: target.hints)
            if results.isEmpty { failure = "IGDB has nothing by that name." }
        } catch IGDBError.rateLimited {
            failure = "IGDB asked us to slow down. Try again in a minute."
        } catch {
            failure = "Couldn't reach IGDB."
        }
    }
}
