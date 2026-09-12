import SwiftUI
import SwiftData

/// Fix Match — re-point a game at the right IGDB entry.
///
/// The Messenger problem, finally with an answer: an id that points at the
/// wrong game poisons everything downstream (generation context, metadata,
/// connected games), and no amount of additive filling can repair it because
/// the wrong data isn't *missing*. The fix has to be a human choosing the
/// right entry — this sheet is that choice, modeled on Plex's Fix Match.
///
/// Search is prefilled with the game's name; a numeric query looks up by id
/// directly (the same trick the Add Game sheet does). Picking a result shows
/// exactly what is replaced and what survives before anything is written.
struct FixMatchView: View {
    let game: Game
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var results: [IGDBGame] = []
    @State private var searching = false
    @State private var failed = false
    @State private var candidate: IGDBGame?

    private var repo: Repository { Repository(context) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Matched to") {
                        Text(game.igdbID.map { "IGDB #\($0)" } ?? "nothing")
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("If this points at the wrong game, everything fetched about it is the wrong game's. Pick the right entry below.")
                }

                Section {
                    if searching {
                        HStack {
                            ProgressView()
                            Text("Searching…").foregroundStyle(.secondary)
                        }
                    } else if failed {
                        Label("Search failed — try again", systemImage: "wifi.exclamationmark")
                            .foregroundStyle(.secondary)
                    } else if results.isEmpty && !searchText.isEmpty {
                        Text("No matches. Try fewer words, or the IGDB id number.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(results) { result in
                        Button {
                            candidate = result
                        } label: {
                            row(result)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Candidates")
                }
            }
            .searchable(text: $searchText, prompt: "Name, or IGDB id")
            .onSubmit(of: .search) { Task { await search() } }
            .navigationTitle("Fix Match")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                searchText = game.name
                await search()
            }
            .confirmationDialog(
                "Rematch to \(candidate?.name ?? "")?",
                isPresented: Binding(get: { candidate != nil },
                                     set: { if !$0 { candidate = nil } }),
                titleVisibility: .visible
            ) {
                Button("Rematch") {
                    if let candidate {
                        repo.rematch(game, to: candidate)
                    }
                    dismiss()
                }
                Button("Cancel", role: .cancel) { candidate = nil }
            } message: {
                Text("Replaces everything fetched — cover, dates, genres, description, series — with \(candidate?.name ?? "this game")'s. Your name for it, platforms, rating, notes, tags, playthroughs and progress stay exactly as they are.")
            }
        }
    }

    private func row(_ result: IGDBGame) -> some View {
        HStack(spacing: 11) {
            CoverThumb(urlString: result.coverURLString)
                .frame(width: 38, height: 51)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(result.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if let type = result.typeLabel {
                        Text(type)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.orange.opacity(0.2), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                }
                Text(subtitle(result))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if result.id == game.igdbID {
                Text("current")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func subtitle(_ result: IGDBGame) -> String {
        var parts: [String] = ["#\(result.id)"]
        if let year = result.releaseYear { parts.append(String(year)) }
        if !result.platforms.isEmpty {
            parts.append(result.platforms.prefix(3).joined(separator: ", "))
        }
        return parts.joined(separator: " · ")
    }

    private func search() async {
        let text = searchText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        searching = true
        failed = false
        defer { searching = false }
        do {
            if let id = Int(text) {
                async let byID = IGDBService.lookup(id: id)
                async let byName = (try? IGDBService.search(name: text)) ?? []
                let direct = try await byID
                results = (direct.map { [$0] } ?? []) + (await byName).filter { $0.id != direct?.id }
            } else {
                results = try await IGDBService.search(name: text)
            }
        } catch {
            failed = true
            results = []
        }
    }
}
