import SwiftUI

/// Add Game: IGDB search-first (by name OR numeric IGDB id), tap a result →
/// quick Platform + Status confirm → Add. Manual entry stays as a fallback
/// for games not on IGDB.
struct AddGameSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @AppStorage("lastPlatform") private var lastPlatform = ""
    @AppStorage("lastStatusRaw") private var lastStatusRaw = GameStatus.playing.rawValue

    @State private var searchText = ""
    @State private var results: [IGDBGame] = []
    @State private var idMatch: IGDBGame?
    @State private var isSearching = false
    @State private var searchFailed = false
    @State private var selected: IGDBGame?
    @State private var manualMode = false

    var body: some View {
        NavigationStack {
            Group {
                if manualMode {
                    manualForm
                } else if let selected {
                    ConfirmAddView(
                        game: selected,
                        lastPlatform: lastPlatform,
                        lastStatus: GameStatus(rawValue: lastStatusRaw) ?? .playing,
                        onBack: { self.selected = nil },
                        onAdd: add(igdb:platform:status:)
                    )
                } else {
                    searchStage
                }
            }
            .navigationTitle(selected == nil ? "Add Game" : "Confirm")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .tint(LSTheme.purple)
    }

    // MARK: Search stage

    private var searchStage: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search IGDB — name or ID number", text: $searchText)
                    .textFieldStyle(.plain)
                    #if !os(macOS)
                    .autocorrectionDisabled()
                    #endif
                if isSearching { ProgressView().controlSize(.small) }
            }
            .padding(12)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
            .padding()

            List {
                if let idMatch {
                    Section("ID match") {
                        resultRow(idMatch, badge: "#\(idMatch.id)")
                    }
                }
                if !results.isEmpty {
                    Section(idMatch == nil ? "Results" : "Name results") {
                        ForEach(results) { game in
                            resultRow(game, badge: nil)
                        }
                    }
                }
                Section {
                    Button {
                        manualMode = true
                    } label: {
                        Label("Add manually (not on IGDB)", systemImage: "square.and.pencil")
                    }
                }
            }
            #if os(macOS)
            .listStyle(.inset)
            #else
            .listStyle(.insetGrouped)
            #endif
            .overlay {
                if searchFailed {
                    ContentUnavailableView(
                        "Search failed",
                        systemImage: "wifi.exclamationmark",
                        description: Text("Check your connection and try again."))
                } else if !isSearching && results.isEmpty && idMatch == nil
                            && searchText.trimmingCharacters(in: .whitespaces).count >= 2 {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
        .task(id: searchText) {
            // Debounce; .task(id:) cancels the previous search automatically.
            try? await Task.sleep(for: .milliseconds(350))
            await runSearch()
        }
    }

    private func resultRow(_ game: IGDBGame, badge: String?) -> some View {
        Button {
            selected = game
        } label: {
            HStack(spacing: 12) {
                CoverThumb(urlString: game.coverURLString)
                    .frame(width: 40, height: 53)
                VStack(alignment: .leading, spacing: 2) {
                    Text(game.name).font(.subheadline.weight(.medium)).lineLimit(2)
                    HStack(spacing: 4) {
                        if let year = game.releaseYear { Text(String(year)) }
                        if let first = game.platforms.first {
                            Text("· \(first)\(game.platforms.count > 1 ? " +\(game.platforms.count - 1)" : "")")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.caption2.monospacedDigit())
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(LSTheme.purple.opacity(0.25), in: .capsule)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func runSearch() async {
        let text = searchText.trimmingCharacters(in: .whitespaces)
        searchFailed = false
        guard text.count >= 2 else {
            results = []; idMatch = nil
            return
        }
        isSearching = true
        defer { isSearching = false }
        do {
            if let numericID = Int(text) {
                // Numeric: id lookup AND name search (some games have numeric names).
                async let byID = IGDBService.lookup(id: numericID)
                async let byName = (try? IGDBService.search(name: text)) ?? []
                idMatch = try await byID
                let named = await byName
                results = named.filter { $0.id != idMatch?.id }
            } else {
                idMatch = nil
                results = try await IGDBService.search(name: text)
            }
        } catch is CancellationError {
            // superseded by newer keystroke — ignore
        } catch {
            if !Task.isCancelled { searchFailed = true }
        }
    }

    // MARK: Manual fallback

    @State private var manualName = ""
    @State private var manualPlatform = ""
    @State private var manualStatus: GameStatus = .playing

    private var manualForm: some View {
        Form {
            Section {
                TextField("Name", text: $manualName)
                TextField("Platform", text: $manualPlatform)
                Picker("Status", selection: $manualStatus) {
                    ForEach(GameStatus.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            }
            Section {
                Button("Add") {
                    let trimmed = manualName.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    let game = Repository(context).addGame(name: trimmed, status: manualStatus)
                    let p = manualPlatform.trimmingCharacters(in: .whitespaces)
                    if !p.isEmpty { game.platforms = [p]; lastPlatform = p }
                    lastStatusRaw = manualStatus.rawValue
                    dismiss()
                }
                .disabled(manualName.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Back to search") { manualMode = false }
            }
        }
        .onAppear {
            manualName = searchText
            manualPlatform = lastPlatform
            manualStatus = GameStatus(rawValue: lastStatusRaw) ?? .playing
        }
    }

    // MARK: Add

    private func add(igdb: IGDBGame, platform: String?, status: GameStatus) {
        Repository(context).addGame(from: igdb, platform: platform, status: status)
        if let platform, !platform.isEmpty { lastPlatform = platform }
        lastStatusRaw = status.rawValue
        dismiss()
    }
}

/// Stage 2: cover + metadata preview, pick Platform + Status, Add.
private struct ConfirmAddView: View {
    let game: IGDBGame
    let lastPlatform: String
    let lastStatus: GameStatus
    var onBack: () -> Void
    var onAdd: (IGDBGame, String?, GameStatus) -> Void

    @State private var platform: String = ""
    @State private var status: GameStatus = .playing

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    CoverThumb(urlString: game.coverURLString)
                        .frame(width: 70, height: 93)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(game.name).font(.headline)
                        HStack(spacing: 4) {
                            if let year = game.releaseYear { Text(String(year)) }
                            if let franchise = game.franchise { Text("· \(franchise)") }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                        Text("IGDB #\(game.id)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Section {
                if game.platforms.isEmpty {
                    TextField("Platform", text: $platform)
                } else {
                    Picker("Platform", selection: $platform) {
                        ForEach(game.platforms, id: \.self) { Text($0).tag($0) }
                    }
                }
                Picker("Status", selection: $status) {
                    ForEach(GameStatus.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            }
            Section {
                Button("Add to Library") {
                    onAdd(game, platform.isEmpty ? nil : platform, status)
                }
                .font(.headline)
                Button("Back to search", action: onBack)
            }
        }
        .onAppear {
            status = lastStatus
            // Prefer the last-used platform when this game supports it.
            if game.platforms.contains(lastPlatform) {
                platform = lastPlatform
            } else {
                platform = game.platforms.first ?? ""
            }
        }
    }
}
