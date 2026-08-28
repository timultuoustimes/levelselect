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
    @State private var importedCount: Int?
    @State private var showingPicker = false

    private enum Stage { case pick, review, done }

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
            .navigationTitle("Import from CSV")
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
                            .disabled(includedCount == 0 || matching)
                    }
                }
            }
            .fileImporter(isPresented: $showingPicker,
                          allowedContentTypes: [.commaSeparatedText, .plainText, .text]) { result in
                handleFile(result)
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
                .padding()
                .background(LSTheme.cardFill, in: .rect(cornerRadius: 14))
                .padding(.horizontal)

                if let importError {
                    Text(importError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
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
                        Text("Looking up games…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
                    CandidateRow(candidate: $candidate)
                }
            } header: {
                HStack {
                    Text("Games")
                    Spacer()
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
            Text("Imported \(importedCount ?? 0) games")
                .font(.title3.bold())
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
    private func matchAll() async {
        matching = true
        matchProgress = 0
        for index in candidates.indices {
            let name = candidates[index].row.name
            let hits = (try? await IGDBService.search(name: name)) ?? []
            let exact = hits.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            candidates[index].match = exact ?? hits.first
            candidates[index].alternatives = Array(hits.prefix(5))
            candidates[index].uncertain = (exact == nil)
            matchProgress = Double(index + 1) / Double(candidates.count)
        }
        matching = false
    }

    private func runImport() {
        let repo = Repository(context)
        var count = 0
        for candidate in candidates where candidate.include {
            let row = candidate.row
            let game: Game
            if let match = candidate.match {
                game = repo.addGame(from: match,
                                    platform: row.platform,
                                    status: row.status ?? .backlog)
            } else {
                game = repo.addGame(name: row.name, status: row.status ?? .backlog)
                if let platform = row.platform { game.platforms = [platform] }
            }
            game.rating = row.rating
            if let notes = row.notes { game.notes = notes }

            // Hours from the CSV become one manual session, so the number
            // shows up in stats without inventing a fake play history.
            if let hours = row.hoursPlayed, hours > 0 {
                let pt = repo.ensureDefaultPlaythrough(for: game)
                repo.logManualSession(on: pt, duration: hours * 3600,
                                      notes: "Imported from CSV")
            }
            count += 1
        }
        BuiltinTrackers.installMissing(context: context)
        PersistenceMonitor.shared.commit(context)
        importedCount = count
        stage = .done
    }
}

/// One reviewable row: what the CSV said, what IGDB found, and a way to change it.
private struct CandidateRow: View {
    @Binding var candidate: CSVImportView.Candidate

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
                    if candidate.uncertain {
                        Label("check", systemImage: "questionmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    // Show the original when IGDB renamed it, so a wrong match
                    // is obvious rather than hidden behind a tidy title.
                    if let match = candidate.match,
                       match.name.caseInsensitiveCompare(candidate.row.name) != .orderedSame {
                        Text("was “\(candidate.row.name)”")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let platform = candidate.row.platform {
                        Text(platform).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer(minLength: 4)

            if candidate.alternatives.count > 1 {
                Menu {
                    ForEach(candidate.alternatives, id: \.id) { option in
                        Button {
                            candidate.match = option
                            candidate.uncertain = false
                        } label: {
                            Text(option.name)
                        }
                    }
                    Divider()
                    Button("Keep “\(candidate.row.name)” as typed") {
                        candidate.match = nil
                        candidate.uncertain = false
                    }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption)
                }
                .accessibilityLabel("Change match")
            }
        }
        .listRowBackground(Color.clear)
    }
}
