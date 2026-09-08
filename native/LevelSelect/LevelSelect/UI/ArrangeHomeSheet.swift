import SwiftUI
import SwiftData

/// Arrange Home — drag, switch on and off, and the systems block's count.
///
/// Same shape as Arrange Sections and Arrange Stats: a list with drag
/// handles and a Done button, because the third arrange sheet in an app
/// should look like the first two. The one difference is written in the
/// footer: **this order follows you to your other devices.** A self-portrait
/// is not a per-device preference.
///
/// Every block that can exist is a row here, hidden ones switched off — so
/// there is no separate "add" menu for Backlog or Finished. Collections are
/// the exception: there can be any number, so pinned ones are rows and the
/// rest live under "Add a collection to Home…".
struct ArrangeHomeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \ThemeSettings.createdAt) private var themeSettings: [ThemeSettings]
    @Query(filter: #Predicate<GameCollection> { $0.deletedAt == nil }, sort: \GameCollection.sortIndex)
    private var collections: [GameCollection]

    /// The device-local hidden set, honored only while nothing is stored.
    /// Once this sheet writes a layout the set is spent — see `HomeLayout.resolve`.
    @AppStorage("homeHiddenStatuses") private var legacyHiddenRaw = ""

    @State private var layout: HomeLayout = .standard
    @State private var arrangingSystems = false

    private var legacyHidden: Set<GameStatus> {
        Set(legacyHiddenRaw.split(separator: ",").compactMap { GameStatus(rawValue: String($0)) })
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(layout.entries) { entry in
                        row(entry)
                    }
                    .onMove { from, to in
                        layout.move(fromOffsets: from, toOffset: to)
                        write()
                    }
                } footer: {
                    Text("Drag to reorder. This order follows you to your other devices. Everything stays in Library whether it's here or not.")
                }

                let unpinned = collections.filter { !layout.pinnedCollections.contains($0.id) }
                if !unpinned.isEmpty {
                    Section {
                        Menu {
                            ForEach(unpinned) { collection in
                                Button {
                                    layout.pin(collection: collection.id)
                                    write()
                                } label: {
                                    Label(collection.name,
                                          systemImage: collection.isSmart ? "sparkles.rectangle.stack" : "rectangle.3.group")
                                }
                            }
                        } label: {
                            Label("Add a collection to Home…", systemImage: "plus")
                        }
                    } footer: {
                        Text("A collection on Home is its own shelf, with its covers under its name. \"Six That Made Me\" says more here than a tile does.")
                    }
                }
            }
            .lsAlwaysEditing()
            .navigationTitle("Arrange Home")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                // A toolbar button, not a row control: in an always-editing
                // list the rows own every tap that is not a toggle, so the
                // way to a second screen has to sit outside them.
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        arrangingSystems = true
                    } label: { Label("Systems", systemImage: "arcade.stick.console") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $arrangingSystems) {
                ArrangeSystemsSheet().lsSheet([.large])
            }
        }
        .onAppear { reload() }
        // The systems sheet writes the same record; pick its changes up.
        .onChange(of: arrangingSystems) { _, open in if !open { reload() } }
    }

    private func reload() {
        layout = HomeLayout.resolve(raw: themeSettings.first?.homeLayoutRaw,
                                    legacyHiddenStatuses: legacyHidden)
    }

    @ViewBuilder
    private func row(_ entry: HomeLayout.Entry) -> some View {
        HStack(spacing: 10) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(entry.block))
                    if let sub = subtitle(entry.block) {
                        Text(sub).font(.caption).foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: icon(entry.block))
                    .foregroundStyle(tint(entry.block))
            }
            Spacer(minLength: 0)
            if entry.block == .systems {
                Text("Show \(layout.systemsCount)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Toggle("", isOn: Binding(
                get: { !entry.hidden },
                set: { on in
                    layout.setHidden(entry.block, !on)
                    write()
                }))
            .labelsHidden()
            .tint(LSTheme.accent)
            .accessibilityLabel(title(entry.block))
        }
        .swipeActions(edge: .trailing) {
            if case .collection(let id) = entry.block {
                Button(role: .destructive) {
                    layout.unpin(collection: id)
                    write()
                } label: { Label("Remove from Home", systemImage: "pin.slash") }
            }
        }
    }

    private func title(_ block: HomeBlock) -> String {
        switch block {
        case .continuePlaying:    "Continue Playing"
        case .systems:            "Systems"
        case .status(let s):      s.sectionTitle
        case .collections:        "Collections"
        case .collection(let id): collections.first { $0.id == id }?.name ?? "A collection"
        }
    }

    private func subtitle(_ block: HomeBlock) -> String? {
        switch block {
        case .systems:
            return layout.systemsStyle == .grid ? "The display case" : "A scrolling row"
        case .collections:
            return "Every collection, as tiles"
        case .collection(let id):
            let c = collections.first { $0.id == id }
            return c?.isSmart == true ? "Smart collection — fills itself" : "Collection"
        default:
            return nil
        }
    }

    private func icon(_ block: HomeBlock) -> String {
        switch block {
        case .continuePlaying:    "play.circle.fill"
        case .systems:            "arcade.stick.console.fill"
        case .status(let s):      s.systemImage
        case .collections:        "rectangle.3.group.fill"
        case .collection(let id):
            collections.first { $0.id == id }?.isSmart == true ? "sparkles.rectangle.stack" : "rectangle.3.group"
        }
    }

    private func tint(_ block: HomeBlock) -> Color {
        if case .status(let s) = block { return s.color }
        return LSTheme.accent
    }

    private func write() {
        let settings = ThemePalette.fetchOrCreate(in: context)
        settings.homeLayoutRaw = layout.raw
        settings.updatedAt = .now
    }
}

/// Arrange Systems as its own sheet — from the Systems header's long-press,
/// and from Arrange Home's toolbar. Owns the layout it edits, since it can
/// open without Arrange Home underneath it.
struct ArrangeSystemsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \ThemeSettings.createdAt) private var themeSettings: [ThemeSettings]
    @AppStorage("homeHiddenStatuses") private var legacyHiddenRaw = ""
    @State private var layout: HomeLayout = .standard

    var body: some View {
        NavigationStack {
            ArrangeSystemsView(layout: $layout) {
                let settings = ThemePalette.fetchOrCreate(in: context)
                settings.homeLayoutRaw = layout.raw
                settings.updatedAt = .now
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .onAppear {
            let legacy = Set(legacyHiddenRaw.split(separator: ",").compactMap { GameStatus(rawValue: String($0)) })
            layout = HomeLayout.resolve(raw: themeSettings.first?.homeLayoutRaw, legacyHiddenStatuses: legacy)
        }
    }
}

/// Arrange Systems — how many reach Home, how they draw, and in what order.
///
/// Tim, 2026-09-05: *"tap into view your consoles, you can select how many
/// you want to show on your Home Screen (the rest stay in view more), and
/// then you can drag the order around from there."* The count and the order
/// are one idea: the ordered list is the preference, the first N of it is
/// what fits on Home, the rest sit behind "See all" in that same order.
///
/// A sort rewrites the list in one tap and drag still wins afterwards — the
/// sort menu then reads "Custom", because that is what it is.
struct ArrangeSystemsView: View {
    @Binding var layout: HomeLayout
    var onChange: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var typeSize
    @Query(filter: #Predicate<Game> { $0.deletedAt == nil }) private var games: [Game]
    @Query(sort: \ThemeSettings.createdAt) private var themeSettings: [ThemeSettings]

    @State private var order: [HomeSystems.Group] = []
    @State private var sort: SystemsSort = .custom
    /// When each console arrived, for the "Order I got them" sort.
    @Query(filter: #Predicate<Console> { $0.deletedAt == nil }) private var consoles: [Console]

    /// Keyed by canonical platform name, and only the ones actually dated —
    /// an entry with no date must not be mistaken for one at the epoch.
    private var acquiredDates: [String: Date] {
        var out: [String: Date] = [:]
        for console in consoles {
            if let date = console.acquiredAt { out[console.platform] = date }
        }
        return out
    }

    private var available: [HomeSystems.Group] {
        var counts: [String: Int] = [:]
        for game in games where game.status != .wishlist {
            let owned = game.ownedPlatformNames
            for platform in (owned.isEmpty ? ["Other"] : owned) {
                counts[platform, default: 0] += 1
            }
        }
        return counts.map { (platform: $0.key, count: $0.value) }
    }

    var body: some View {
        List {
            Section {
                Stepper(value: Binding(
                    get: { layout.systemsCount },
                    set: { layout.systemsCount = $0; onChange() }),
                        in: HomeLayout.systemsCountRange,
                        step: layout.systemsStyle == .grid && !typeSize.isAccessibilitySize ? 3 : 1) {
                    HStack {
                        Text("Show on Home")
                        Spacer()
                        Text("\(layout.systemsCount)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                Picker("Shape", selection: Binding(
                    get: { layout.systemsStyle },
                    set: { layout.systemsStyle = $0; onChange() })) {
                    ForEach(SystemsBlockStyle.allCases) { style in
                        Label(style.label, systemImage: style.systemImage).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                Picker("Sort", selection: $sort) {
                    ForEach(SystemsSort.allCases) { s in
                        Label(s.label, systemImage: s.systemImage).tag(s)
                    }
                }
                .onChange(of: sort) { _, new in
                    guard new != .custom else { return }
                    order = HomeSystems.sorted(order, by: new, acquired: acquiredDates)
                    write()
                }
            } footer: {
                Text(layout.systemsStyle == .grid
                     ? "The case is three across, so it steps by three. Pick Row for a scrolling shelf that fits any number."
                     : "A row scrolls, so any number fits.")
            }

            Section {
                ForEach(Array(order.enumerated()), id: \.element.platform) { index, g in
                    HStack(spacing: 12) {
                        PlatformIconView(platform: g.platform, size: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(PlatformShort.name(g.platform))
                            HStack(spacing: 6) {
                                if let year = PlatformEra.releaseYear(g.platform) {
                                    Text(String(year))
                                }
                                Text(Format.gameCount(g.count))
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if index == layout.systemsCount - 1, order.count > layout.systemsCount {
                            // The line between Home and "See all", drawn on
                            // the last tile that makes it rather than as a
                            // divider the list cannot drag across.
                            Text("Last on Home")
                                .font(.caption2)
                                .foregroundStyle(LSTheme.accent)
                        }
                    }
                    .opacity(index < layout.systemsCount ? 1 : 0.55)
                }
                .onMove { from, to in
                    order.move(fromOffsets: from, toOffset: to)
                    sort = .custom
                    write()
                }
            } header: {
                Text("Your order")
            } footer: {
                Text(order.count > layout.systemsCount
                     ? "The first \(layout.systemsCount) are on Home. The rest are in See all, in this order."
                     : "All \(order.count) fit on Home.")
            }
        }
        .lsAlwaysEditing()
        .navigationTitle("Arrange Systems")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            let raw = themeSettings.first?.homeSystemsRaw
            order = HomeSystems.ordered(raw: raw, available: available)
            sort = HomeSystems.parse(raw).sort
        }
    }

    private func write() {
        let settings = ThemePalette.fetchOrCreate(in: context)
        settings.homeSystemsRaw = HomeSystems.raw(order: order.map(\.platform), sort: sort)
        settings.updatedAt = .now
    }
}


/// Drag handles always showing, where the platform has them. macOS lists
/// reorder without an edit mode, and the modifier does not exist there.
private struct AlwaysEditing: ViewModifier {
    func body(content: Content) -> some View {
        #if os(macOS)
        content
        #else
        content.environment(\.editMode, .constant(.active))
        #endif
    }
}

extension View {
    func lsAlwaysEditing() -> some View { modifier(AlwaysEditing()) }
}
