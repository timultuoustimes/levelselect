import SwiftUI
import SwiftData

/// Wishlist → You Might Like: games drawn from your own library, in three
/// shelves, each row saying which of your games it came from.
///
/// Nothing here is trending or popular — see `Suggestions`. A row you don't
/// want goes away for good ("Not interested"), and the list is asked for once
/// a day unless you pull to refresh.
struct SuggestionsPane: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Game> { $0.deletedAt == nil }) private var games: [Game]

    @State private var items: [Suggestions.Item] = []
    @State private var loading = false
    @State private var error: String?
    /// When the shown suggestions are an older copy because refreshing failed.
    @State private var staleSince: Date?
    @State private var adding: String?
    @State private var loaded = false
    @State private var tuning = false
    /// Remembered, because the answer to "which systems do I care about" does
    /// not change between visits.
    @AppStorage("levelselect.suggestions.system") private var system = ""
    @AppStorage("levelselect.suggestions.sort") private var sortRaw = Suggestions.Sort.date.rawValue

    private var sort: Suggestions.Sort {
        Suggestions.Sort(rawValue: sortRaw) ?? .date
    }

    /// Your systems, most active first — the order the chips are offered in.
    private var systems: [String] {
        Suggestions.activeSystems(from: games.map {
            (platforms: $0.ownedPlatformNames,
             lastPlayed: $0.activePlaythrough?.lastPlayedAt,
             addedAt: $0.addedAt)
        })
    }

    private var shown: [Suggestions.Item] {
        Suggestions.weighted(
            Suggestions.allowed(Suggestions.onSystem(system.isEmpty ? nil : system, items)))
    }

    @ScaledMetric(relativeTo: .caption2) private var coverWidth: CGFloat = 64

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if loading && items.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Looking at what you've played…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 24)
                } else if let error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(LSTheme.working)
                } else if items.isEmpty {
                    empty
                } else {
                    if let staleSince {
                        Label("Couldn't refresh — these are from \(staleSince.formatted(.relative(presentation: .named))).",
                              systemImage: "clock.arrow.circlepath")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    controls
                    if shown.isEmpty {
                        Text("Nothing here is on \(PlatformShort.name(system)). Try another system, or All.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    }
                    ForEach(Suggestions.Shelf.allCases) { shelf in
                        let shelfItems = Suggestions.sorted(shown.filter { $0.shelf == shelf },
                                                            by: sort, shelf: shelf)
                        if !shelfItems.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(shelf.label)
                                    .font(.headline)
                                ForEach(shelfItems) { item in
                                    row(item)
                                }
                            }
                        }
                    }
                    Text("From games you've rated, played or finished, and what's announced in their series. Nothing here is trending or popular.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .refreshable { await load(force: true) }
        .sheet(item: Binding(get: { adding.map(IdentifiedName.init) },
                             set: { adding = $0?.name })) { target in
            AddGameSheet(initialSearch: target.name, defaultStatus: .wishlist).lsSheet()
        }
        .sheet(isPresented: $tuning) {
            SuggestionPrefsSheet(games: games)
        }
        .task {
            guard !loaded else { return }
            loaded = true
            await load()
        }
    }

    /// The filter and sort this pane owns. On the pane rather than in the
    /// tab's toolbar menu, because that menu sorts YOUR wishlist and did
    /// nothing here — Tim, 09-17: *"sort doesn't do anything for you might
    /// like or the Deku deals sections."*
    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip("All", selected: system.isEmpty) { system = "" }
                    ForEach(systems, id: \.self) { name in
                        chip(PlatformShort.name(name), selected: system == name) {
                            system = system == name ? "" : name
                        }
                    }
                }
            }
            HStack {
                Menu {
                    Picker("Sort", selection: $sortRaw) {
                        ForEach(Suggestions.Sort.allCases) { option in
                            Label(option.label, systemImage: option.systemImage).tag(option.rawValue)
                        }
                    }
                } label: {
                    Label(sort.label, systemImage: "arrow.up.arrow.down")
                        .font(.caption)
                }
                Button {
                    tuning = true
                } label: {
                    Label("What you're into", systemImage: "slider.horizontal.3")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                Spacer()
                Text("\(shown.count) game\(shown.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(selected ? LSTheme.accent.opacity(0.25) : Color.secondary.opacity(0.12),
                            in: .capsule)
                .foregroundStyle(selected ? AnyShapeStyle(LSTheme.accent) : AnyShapeStyle(.primary))
        }
        .buttonStyle(.plain)
        .lsTapTargetInline()
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private struct IdentifiedName: Identifiable {
        let name: String
        var id: String { name }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nothing to suggest yet")
                .font(.headline)
            Text("Rate a few games, or finish one, and this fills up with what they're like. Your library is the only thing it reads.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Look again") { Task { await load(force: true) } }
                .buttonStyle(.borderless)
        }
        .padding(.top, 24)
    }

    private func row(_ item: Suggestions.Item) -> some View {
        HStack(alignment: .top, spacing: 12) {
            cover(item)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if let when = item.releaseText {
                        Text(when)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text("because you played \(item.because)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                    if let tag = item.tag {
                        Text(tag)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(LSTheme.accent.opacity(0.18), in: .capsule)
                            .foregroundStyle(LSTheme.accent)
                    }
                }
                HStack(spacing: 10) {
                    Button {
                        adding = item.name
                    } label: {
                        Label("Add to Wishlist", systemImage: "bag.badge.plus")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.borderless)
                    Button {
                        SuggestionsService.hide(item.id)
                        withAnimation(.snappy) { items.removeAll { $0.id == item.id } }
                    } label: {
                        Text("Not interested")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func cover(_ item: Suggestions.Item) -> some View {
        let url = item.coverImageID.flatMap {
            URL(string: "https://images.igdb.com/igdb/image/upload/t_cover_big/\($0).jpg")
        }
        AsyncImage(url: url) { phase in
            if case .success(let image) = phase {
                image.resizable().scaledToFill()
            } else {
                LSTheme.accent.opacity(0.12)
            }
        }
        .frame(width: coverWidth, height: coverWidth * 4 / 3)
        .clipShape(.rect(cornerRadius: 6))
        .accessibilityHidden(true)
    }

    private func load(force: Bool = false) async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            items = try await SuggestionsService.suggestions(for: games, force: force)
            staleSince = nil
        } catch {
            if let last = SuggestionsService.lastKnown() {
                items = last.items
                staleSince = last.madeAt
            } else {
                self.error = "Couldn't reach IGDB for suggestions."
            }
        }
    }
}
