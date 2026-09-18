import SwiftUI
import SwiftData

/// Wishlist → You Might Like → What you're into.
///
/// Follow a studio, a publisher, a tag or a system and its games come first;
/// hide one and they never appear. The lists are drawn from your own library,
/// plus your vocabulary's terms, so there's nothing to search a catalog for.
struct SuggestionPrefsSheet: View {
    let games: [Game]
    @Environment(\.dismiss) private var dismiss

    @State private var kind: SuggestionPrefs.Kind = .studio
    /// Redrawn on every change, since the stance lives in UserDefaults rather
    /// than in view state.
    @State private var version = 0
    @State private var search = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Kind", selection: $kind) {
                        ForEach(SuggestionPrefs.Kind.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(kind.blurb)
                }

                Section {
                    ForEach(rows, id: \.self) { name in
                        row(name)
                    }
                    if rows.isEmpty {
                        Text(kind == .tag
                             ? "Tag a few games and they'll show up here."
                             : "Nothing here yet — add some games and this fills in.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Followed comes first, and everything else is still there, lightly scattered. Hidden never appears. Kept on this device.")
                }
            }
            .searchable(text: $search, prompt: "Search \(kind.label.lowercased())")
            .lsFormStyle()
            .navigationTitle("What You're Into")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .lsSheet()
    }

    private func row(_ name: String) -> some View {
        let stance = { _ = version; return SuggestionPrefs.stance(kind, name) }()
        return HStack {
            Text(name)
                .lineLimit(1)
            Spacer()
            Button {
                SuggestionPrefs.set(stance == .followed ? .neutral : .followed, kind, name)
                version += 1
            } label: {
                Image(systemName: stance == .followed ? "star.fill" : "star")
                    .foregroundStyle(stance == .followed ? AnyShapeStyle(LSTheme.accent)
                                     : AnyShapeStyle(.secondary))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(stance == .followed ? "Following \(name). Stop following" : "Follow \(name)")
            Button {
                SuggestionPrefs.set(stance == .hidden ? .neutral : .hidden, kind, name)
                version += 1
            } label: {
                Image(systemName: stance == .hidden ? "eye.slash.fill" : "eye.slash")
                    .foregroundStyle(stance == .hidden ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(stance == .hidden ? "\(name) is hidden. Show it again" : "Hide \(name)")
        }
    }

    /// What to offer, most-owned first, filtered by the search field.
    private var rows: [String] {
        let all: [String]
        switch kind {
        case .studio:    all = ranked(games.flatMap(\.developers))
        case .publisher: all = ranked(games.flatMap(\.publishers))
        case .tag:
            // Your own words first, then the rest of the vocabulary, so a term
            // you have never used is still followable.
            let mine = Suggestions.taste(from: games.map(\.userTags))
            all = mine + SuggestedTags.all.map(\.name).filter { !mine.contains($0) }
        case .system:
            all = Suggestions.activeSystems(from: games.map {
                (platforms: $0.ownedPlatformNames,
                 lastPlayed: $0.activePlaythrough?.lastPlayedAt,
                 addedAt: $0.addedAt)
            }, limit: 40).map(PlatformShort.name)
        }
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return all }
        return all.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    /// Names by how many of your games carry them.
    private func ranked(_ names: [String]) -> [String] {
        var counts: [String: Int] = [:]
        var display: [String: String] = [:]
        for name in names {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let key = SuggestionPrefs.fold(trimmed)
            counts[key, default: 0] += 1
            display[key] = display[key] ?? trimmed
        }
        return counts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .compactMap { display[$0.key] }
    }
}
