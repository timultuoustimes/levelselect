import SwiftUI
import SwiftData

/// What opens the viewer, and in what state.
struct MapViewerTarget: Identifiable {
    let id = UUID()
    let game: Game
    /// Which map to show first; nil means the first map the game has.
    var map: GameMap? = nil
    /// Arrive in place mode with this item already chosen — the "＋📍" on a
    /// tracker row. Two taps from "where is it" to a pin that ticks.
    var placingItem: TrackerItemDTO? = nil
    /// Arrive pinning this tracker category, one tap per spot.
    var pinningCategoryID: String? = nil
}

/// What part of a map is on screen, shared by the pane and the expanded map
/// so that moving one moves the other.
///
/// Tim, 09-12: *"it should stay zoomed in and centered at whatever you can
/// see on screen when it was full screen, and then if I move the view in the
/// smaller pane then vice versa."* So it records what you were LOOKING AT, not
/// the numbers that produced it in one view: the map point under the middle,
/// and how large the map is drawn in absolute terms. The same island is then
/// the same size in both views — the pane simply shows less around it. A zoom
/// relative to "fitted" would have shrunk it on the way back down, because
/// the pane's fit is smaller.
struct MapViewport: Equatable {
    var mapID: UUID?
    /// The map point, 0…1 on each axis, under the middle of the view.
    var center = CGPoint(x: 0.5, y: 0.5)
    /// Screen points per image pixel. Nil means fitted, whatever the view.
    var pointsPerPixel: CGFloat?

    static let zoomRange: ClosedRange<CGFloat> = 1...8

    /// The zoom and pan that show this in a view whose fitted image is `fitted`.
    /// A scale the view cannot honor clamps to its range; the center holds.
    func transform(pixel: CGSize, fitted: CGSize) -> (zoom: CGFloat, pan: CGSize) {
        guard fitted.width > 0, fitted.height > 0, pixel.width > 0 else { return (1, .zero) }
        let base = fitted.width / pixel.width
        let zoom = pointsPerPixel.map {
            min(max($0 / base, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        } ?? 1
        // The transform is anchored at the view's center: a content point p
        // appears at center + (p − fitted/2)·zoom + pan. Solving for the pan
        // that puts `center` there.
        return (zoom, CGSize(width: (0.5 - center.x) * fitted.width * zoom,
                             height: (0.5 - center.y) * fitted.height * zoom))
    }

    /// What a view with this zoom and pan is showing.
    static func captured(mapID: UUID?, zoom: CGFloat, pan: CGSize,
                         pixel: CGSize, fitted: CGSize) -> MapViewport {
        guard fitted.width > 0, fitted.height > 0, pixel.width > 0, zoom > 0 else {
            return MapViewport(mapID: mapID)
        }
        return MapViewport(
            mapID: mapID,
            center: CGPoint(x: 0.5 - pan.width / zoom / fitted.width,
                            y: 0.5 - pan.height / zoom / fitted.height),
            pointsPerPixel: zoom > 1.001 ? zoom * fitted.width / pixel.width : nil)
    }
}

/// A pin that belongs to a tracker item takes its look from the list the item
/// is in: the category's name, an icon read from that name, a color that
/// stays put.
///
/// The roadmap filed "custom names and icons for pin types" as blocked on a
/// schema change, because `Marker` has no type field. For a LINKED pin that
/// was never true: it already records its tracker item, and the item's
/// category is the type. So Bosses are crowns and Grubs are ladybugs with no
/// new field and no CloudKit deploy. Only a free-standing pin still has just
/// the four kinds, and choosing an icon by hand is the part that would need
/// somewhere to keep the choice.
enum PinStyle {
    /// First match wins, and a key matches the START of a word — so
    /// "Whispering Roots" is a root, not a ring, and "Mask Shards" is a mask
    /// before it is a shard.
    static let table: [(keys: [String], symbol: String)] = [
        (["boss"], "crown.fill"),
        (["ship", "boat"], "sailboat.fill"),
        (["grub", "bug", "insect", "beetle"], "ladybug.fill"),
        (["key"], "key.fill"),
        (["chest", "treasure", "loot"], "shippingbox.fill"),
        (["mask", "heart", "health", "life"], "heart.fill"),
        (["vessel", "soul", "mana"], "drop.fill"),
        (["spell", "magic", "abilit", "skill"], "flame.fill"),
        (["charm", "trinket", "amulet", "ring"], "sparkles"),
        (["quest", "mission", "story", "chapter"], "scroll.fill"),
        (["achievement", "troph"], "trophy.fill"),
        (["armor", "armour", "shield", "helm"], "shield.fill"),
        (["weapon", "sword", "nail", "blade", "tool"], "hammer.fill"),
        (["upgrade", "ore", "gem", "crystal", "shard", "material"], "diamond.fill"),
        (["coin", "gold", "money", "geo", "rupee", "currenc"], "dollarsign.circle.fill"),
        (["dream", "moon"], "moon.stars.fill"),
        (["root", "korok", "seed", "plant", "tree", "flower"], "leaf.fill"),
        (["idol", "seal", "relic", "egg", "artifact", "journal", "statue"], "seal.fill"),
        (["dungeon", "cave", "door", "room"], "door.left.hand.open"),
        (["ending", "finale"], "flag.checkered"),
        (["shrine", "temple", "colosseum", "pantheon", "arena", "tower"], "building.columns.fill"),
        (["fish"], "fish.fill"),
        (["npc", "character", "merchant", "shop", "vendor", "companion"], "person.fill"),
        (["secret", "hidden"], "eye.slash.fill"),
        (["map", "location", "area", "region"], "map.fill"),
        (["star", "collectible", "item"], "star.fill"),
    ]
    static let fallback = "mappin"
    static var allSymbols: [String] { table.map(\.symbol) + [fallback] }

    /// What the picker offers: everything the names can reach, then shapes
    /// and things no category name suggests.
    static var choices: [String] {
        let extras = [
            "flag.fill", "gift.fill", "bell.fill", "lightbulb.fill", "puzzlepiece.fill",
            "gamecontroller.fill", "book.fill", "music.note", "pawprint.fill", "bird.fill",
            "tortoise.fill", "hare.fill", "tent.fill", "house.fill", "mountain.2.fill",
            "globe.americas.fill", "sun.max.fill", "snowflake", "bolt.fill", "hourglass",
            "cart.fill", "wrench.and.screwdriver.fill", "exclamationmark.triangle.fill",
            "questionmark", "hexagon.fill", "triangle.fill", "circle.fill", "square.fill",
        ]
        var seen = Set<String>()
        return (table.map(\.symbol) + extras + [fallback]).filter { seen.insert($0).inserted }
    }

    /// Colors a list can be given, by name so a stored choice means the same
    /// color on every device and every future palette tweak. The first
    /// `automaticColorCount` are the automatic palette, in the order
    /// `paletteIndex` picks from — so no existing pin changed color when these
    /// became choosable.
    static let colorNames = ["orange", "teal", "pink", "yellow", "mint", "cyan", "indigo",
                             "brown", "green", "coral", "red", "blue", "purple", "gray"]
    static let automaticColorCount = 10

    static func symbol(for category: TrackerCategoryDTO) -> String {
        category.pinSymbol ?? symbol(forCategory: category.name)
    }

    static func colorName(for category: TrackerCategoryDTO) -> String {
        if let chosen = category.pinColor, colorNames.contains(chosen) { return chosen }
        return colorNames[paletteIndex(for: category.id, count: automaticColorCount)]
    }

    static func color(named name: String) -> Color {
        switch name {
        case "orange": .orange
        case "teal":   .teal
        case "pink":   .pink
        case "yellow": .yellow
        case "mint":   .mint
        case "cyan":   .cyan
        case "indigo": .indigo
        case "brown":  .brown
        case "green":  .green
        case "coral":  Color(red: 0.93, green: 0.42, blue: 0.33)
        case "red":    .red
        case "blue":   .blue
        case "purple": .purple
        default:       .gray
        }
    }

    static func symbol(forCategory name: String) -> String {
        let words = name.lowercased()
            .split(whereSeparator: { !$0.isLetter })
            .map(String.init)
        for entry in table
        where words.contains(where: { word in entry.keys.contains(where: { word.hasPrefix($0) }) }) {
            return entry.symbol
        }
        return fallback
    }

    /// A stable slot in a palette. Swift's `hashValue` is reseeded every
    /// launch, so a category colored by it would change color each time the
    /// app opened; djb2 over the id's bytes gives the same answer forever.
    static func paletteIndex(for id: String, count: Int) -> Int {
        var hash: UInt64 = 5381
        for byte in id.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return Int(hash % UInt64(max(count, 1)))
    }
}

/// Pinning a whole tracker list, one tap per spot.
///
/// Tim, 09-08: *"I am pinning items from the tracker > this category > select
/// the item > drop the pin. that window stays open as a sidebar on ipad, or
/// just minimizes and opens back up where you left off on iphone until you
/// explicitly hit done… grubs - forgotten crossroads > tap every location
/// where a grub is > done."*
struct PinSession: Equatable {
    var categoryID: String
    /// The item the next tap pins. Nil once every item in the list has one.
    var itemID: String?
    /// Folded down to a bar on a narrow screen, so the map is all yours.
    var minimized = false
    /// The pin the last tap made, for Undo.
    var lastPinID: UUID?
}

/// Choosing a list's pin, for this game only.
///
/// Tim, 09-13: *"I think only for that game seems right."* The automatic
/// icon reads the category's name, so a list called "Warrior Graves" gets the
/// plain pin — and with ten automatic colors, two such lists on one map can
/// look identical. This is the way out of both.
struct PinStylePicker: View {
    let game: Game
    let category: TrackerCategoryDTO
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var symbol: String?
    @State private var color: String?

    private var shownSymbol: String { symbol ?? PinStyle.symbol(forCategory: category.name) }
    private var shownColor: String {
        color ?? PinStyle.colorNames[PinStyle.paletteIndex(for: category.id,
                                                           count: PinStyle.automaticColorCount)]
    }
    private let columns = [GridItem(.adaptive(minimum: 44), spacing: 8)]

    var body: some View {
        NavigationStack {
            LSForm {
                Section {
                    HStack {
                        Spacer()
                        ZStack {
                            Circle()
                                .fill(PinStyle.color(named: shownColor))
                                .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                                .frame(width: 56, height: 56)
                            Image(systemName: shownSymbol)
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
                        .accessibilityHidden(true)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                } footer: {
                    Text("Every \(category.name) pin in \(game.name). Other games keep their own.")
                }

                Section("Icon") {
                    LazyVGrid(columns: columns, spacing: 8) {
                        cell(selected: symbol == nil, label: "Automatic icon") {
                            symbol = nil
                        } content: {
                            Text("Auto").font(.caption2.weight(.semibold))
                        }
                        ForEach(PinStyle.choices, id: \.self) { name in
                            cell(selected: symbol == name, label: name) {
                                symbol = name
                            } content: {
                                Image(systemName: name).font(.system(size: 17, weight: .semibold))
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Color") {
                    LazyVGrid(columns: columns, spacing: 8) {
                        cell(selected: color == nil, label: "Automatic color") {
                            color = nil
                        } content: {
                            Text("Auto").font(.caption2.weight(.semibold))
                        }
                        ForEach(PinStyle.colorNames, id: \.self) { name in
                            Button {
                                color = name
                            } label: {
                                Circle()
                                    .fill(PinStyle.color(named: name))
                                    .frame(width: 30, height: 30)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(.primary, lineWidth: color == name ? 3 : 0)
                                            .padding(-5))
                                    .frame(width: 44, height: 44)
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(name.capitalized)
                            .accessibilityAddTraits(color == name ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(category.name)
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Repository(context).setPinStyle(game, categoryID: category.id,
                                                        symbol: symbol, color: color)
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            symbol = category.pinSymbol
            color = category.pinColor
        }
    }

    private func cell<Content: View>(selected: Bool, label: String,
                                     action: @escaping () -> Void,
                                     @ViewBuilder content: () -> Content) -> some View {
        Button(action: action) {
            content()
                .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .frame(width: 44, height: 44)
                .background(selected ? AnyShapeStyle(LSTheme.accent) : AnyShapeStyle(LSTheme.cardFill),
                            in: .rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The map, full screen: pinch and pan, pins where things are, and the two
/// ways a pin gets there.
///
/// **Place mode is the reliable door; long-press is the quick one.** Place
/// mode puts a ring at the center and you pan the map under it, which works
/// at any zoom and needs no explanation. Long-press drops a pin under the
/// finger for people who expect that, and opens its card so it is never a
/// nameless dot. Both make the same marker.
///
/// **The legend is the filter.** Four kinds, four colors, tap one to hide
/// that kind; "Left" and "Explored" split the rest. One control doing two
/// jobs, on purpose — a separate filter menu would be a third row on a bar
/// that already covers art.
struct MapViewerView: View {
    let target: MapViewerTarget
    /// Full screen from the tracker and the game page, or inside the stage's
    /// side column beside them. Same canvas, pins, gestures and place mode
    /// either way — only the chrome around it changes. A second
    /// implementation of this would be a second set of gesture bugs.
    var embedded: Bool = false
    /// Sharing the column with a video: the header's row costs more height
    /// than its contents earn, so the name and the menu become a floating
    /// cluster over the map instead. Tim, 09-12: *"the header for Maps and
    /// the map name World, plus the video selection and link paste bar take
    /// up more than half of the video space."*
    var dense: Bool = false
    /// Pops the map out over the whole stage and back. Non-nil only in a pane.
    var onToggleExpand: (() -> Void)? = nil
    var expanded: Bool = false
    /// Shared with the other copy of this map on the stage. Nil full screen.
    var viewport: Binding<MapViewport>? = nil
    /// What the floating tab bar covers at the bottom. The stage runs its
    /// panes to the screen edge, so on a phone in landscape the legend and
    /// Place sat underneath the tab bar, cut in half.
    var bottomInset: CGFloat = 0
    /// A list being pinned, shared with the other copy of this map on the
    /// stage so expanding mid-list doesn't lose your place. Nil full screen,
    /// where the session lives in this view.
    var pinning: Binding<PinSession?>? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var currentMapID: UUID?
    /// Pin types the legend has switched off, by `PinType.id`.
    @State private var hiddenTypes: Set<String> = []
    @State private var localPinning: PinSession?
    /// A list whose pin icon is being chosen.
    @State private var stylingCategory: TrackerCategoryDTO?
    /// The last tap that pinned, so a double tap makes one pin rather than two.
    @State private var lastSessionTap: (point: CGPoint, at: Date)?
    @State private var showing: Showing = .all
    @State private var placing: Placing?
    @State private var editing: Marker?
    @State private var renaming = false
    @State private var confirmingDelete = false
    @State private var mapName = ""
    @State private var mapKind: MapKind = .other

    // Zoom and pan, committed plus in-flight.
    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var drag: CGSize = .zero
    /// Where the finger last went down, in map points — read by the
    /// long-press, which has no location of its own.
    @State private var lastTouch: CGPoint?

    private var repo: Repository { Repository(context) }
    private var game: Game { target.game }

    enum Showing: String, CaseIterable, Identifiable {
        case all, left, explored
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all:      "All"
            case .left:     "Left"
            case .explored: "Explored"
            }
        }
    }

    struct Placing {
        var item: TrackerItemDTO?
        /// An existing pin being moved, rather than a new one being dropped.
        var moving: Marker? = nil
    }

    private var maps: [GameMap] { repo.liveMaps(of: game) }
    private var map: GameMap? {
        // The shared view names a map too, so expanding shows the map you
        // picked in the pane rather than the game's first one.
        maps.first(where: { $0.id == currentMapID })
            ?? maps.first(where: { $0.id == viewport?.wrappedValue.mapID })
            ?? target.map ?? maps.first
    }
    private var markers: [Marker] { map.map(repo.liveMarkers(of:)) ?? [] }
    private var states: [String: TrackerStateRecord] {
        let pt = game.activePlaythrough
        return Dictionary((pt?.trackerStates ?? []).filter { $0.deletedAt == nil }.map { ($0.itemID, $0) },
                          uniquingKeysWith: { a, _ in a })
    }
    private var items: [String: TrackerItemDTO] {
        var out: [String: TrackerItemDTO] = [:]
        for cat in game.trackerSchema.map({ TrackerSchemaJSON.categories(from: $0.jsonData) }) ?? [] {
            for item in cat.items { out[item.id] = item }
        }
        return out
    }

    /// `counted` — the items that are totals, not checkboxes — comes from the
    /// caller, built once per pass: a pin on one of those is a spot, not the
    /// item, and reads its own stamp.
    private func explored(_ marker: Marker, _ counted: Set<String>) -> Bool {
        repo.isExplored(marker, states: states, counted: counted)
    }

    private var countedIDs: Set<String> {
        Set(trackerCategories.flatMap(\.items).filter { ($0.countTarget ?? 0) > 0 }.map(\.id))
    }

    private func visibleMarkers(_ index: [String: TrackerCategoryDTO],
                                _ counted: Set<String>) -> [Marker] {
        markers.filter { m in
            !hiddenTypes.contains(pinType(m, index).id)
            && (showing == .all || (showing == .explored) == explored(m, counted))
        }
    }

    /// With the user's own item names, the way the tracker shows them.
    private var trackerCategories: [TrackerCategoryDTO] { repo.trackerCategories(for: game) }

    /// Tracker item id → the category it sits in. Built once per pass and
    /// handed down, because every pin asks.
    private var categoryOfItem: [String: TrackerCategoryDTO] {
        var out: [String: TrackerCategoryDTO] = [:]
        for category in trackerCategories {
            for item in category.items { out[item.id] = category }
        }
        return out
    }

    struct PinType: Identifiable {
        let id: String
        let label: String
        let symbol: String
        let color: Color
    }

    private func pinType(_ marker: Marker, _ index: [String: TrackerCategoryDTO]) -> PinType {
        if let itemID = marker.linkedTrackerItemID, let category = index[itemID] {
            return PinType(id: "cat:" + category.id, label: category.name,
                           symbol: PinStyle.symbol(for: category),
                           color: PinStyle.color(named: PinStyle.colorName(for: category)))
        }
        let kind = marker.category
        return PinType(id: "kind:" + kind.rawValue, label: kind.label,
                       symbol: kind.systemImage, color: color(kind))
    }

    /// The types with pins on this map, in the tracker's own order, then the
    /// four kinds.
    private func legend(_ index: [String: TrackerCategoryDTO]) -> [(type: PinType, count: Int)] {
        var counts: [String: Int] = [:]
        var types: [String: PinType] = [:]
        for marker in markers {
            let type = pinType(marker, index)
            counts[type.id, default: 0] += 1
            types[type.id] = type
        }
        let order = trackerCategories.map { "cat:" + $0.id }
            + MarkerCategory.allCases.map { "kind:" + $0.rawValue }
        return order.compactMap { id in types[id].map { (type: $0, count: counts[id] ?? 0) } }
    }

    var body: some View {
        Group {
            if embedded {
                VStack(spacing: 0) {
                    if !dense {
                        paneHeader
                        Divider()
                    }
                    workArea
                }
            } else {
                fullScreen
            }
        }
        // These hang off BOTH modes. Left inside the NavigationStack they
        // would be full-screen only, so renaming or deleting a map from the
        // pane silently did nothing.
        .sheet(item: $editing) { marker in
            MarkerCard(marker: marker, game: game) {
                placing = Placing(item: nil, moving: marker)
            }
            .lsSheet()
        }
        .sheet(item: $stylingCategory) { category in
            PinStylePicker(game: game, category: category)
                .lsSheet()
        }
        .alert("Rename map", isPresented: $renaming) {
            TextField("Name", text: $mapName)
            Button("Save") { if let map { repo.rename(map, to: mapName, kind: mapKind) } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete \"\(map?.name ?? "")\"?", isPresented: $confirmingDelete,
                            titleVisibility: .visible) {
            Button("Delete Map", role: .destructive) {
                if let map { repo.deleteMap(map) }
                if maps.isEmpty { dismiss() } else { currentMapID = maps.first?.id }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The map and its pins go to Recently Deleted for 30 days.")
        }
        .onAppear {
            currentMapID = viewport?.wrappedValue.mapID ?? target.map?.id ?? maps.first?.id
            if let item = target.placingItem { placing = Placing(item: item) }
            if let categoryID = target.pinningCategoryID { startPinning(categoryID) }
        }
    }

    /// The map itself: the picture, the pins on it, and the ring when placing.
    private var canvasStack: some View {
        ZStack {
            // In a pane the black must stop at the pane's edges; only the
            // full-screen route owns the safe area.
            Color.black.ignoresSafeArea(edges: embedded ? [] : .all)
            if let map, let image = repo.image(for: map), let data = image.data {
                canvas(data: data, pixel: CGSize(width: max(image.pixelWidth, 1),
                                                 height: max(image.pixelHeight, 1)))
            } else {
                ContentUnavailableView("No map image",
                                       systemImage: "map",
                                       description: Text("This map's picture isn't on this device."))
                    .foregroundStyle(.white)
            }
            if placing != nil { crosshair }
        }
        // **Everything you can see, you can touch.**
        //
        // `scaleEffect` draws outside its frame, but hit testing stops at
        // that frame — so a zoomed map spilled past the pane's edge and the
        // spill was inert: taps went through to the tracker and the videos
        // behind it. Pan far enough and the only reachable part of the map
        // was gone, with no way to drag it back. Tim, 09-12: *"any part of
        // the map that's not in the map panel itself isn't tappable… the only
        // thing I could do to move the map at that point was to close the map
        // panel."* Clipping keeps the map inside the pane, where the gestures
        // are. Full screen this changes nothing — the canvas already fills it.
        .clipped()
        .overlay(alignment: .topTrailing) { if embedded { paneControls } }
        // While a list is being pinned, the list's own panel is the control
        // surface; the legend would sit under (or behind) it.
        .overlay(alignment: .bottom) { if session == nil { toolbar } }
    }

    /// Expand/collapse, plus the map's own menu when the header is hidden.
    /// Floating, so it costs the map no height.
    @ViewBuilder
    private var paneControls: some View {
        HStack(spacing: 6) {
            if dense, let map {
                mapMenu(map)
                    .padding(7)
                    .background(.black.opacity(0.55), in: .circle)
            }
            if let onToggleExpand {
                Button { onToggleExpand() } label: {
                    Image(systemName: expanded
                          ? "arrow.down.right.and.arrow.up.left"
                          : "arrow.up.left.and.arrow.down.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(7)
                        .background(.black.opacity(0.55), in: .circle)
                }
                .buttonStyle(.plain)
                .lsTapTarget()
                .accessibilityLabel(expanded ? "Put the map back in its panel"
                                             : "Expand the map over the stage")
            }
        }
        .padding(10)
    }

    /// Rename, source, delete — shared by the pane header and, when that
    /// header is hidden, the floating cluster.
    private func mapMenu(_ map: GameMap) -> some View {
        Menu {
            Button {
                mapName = map.name; mapKind = map.kind; renaming = true
            } label: { Label("Rename Map…", systemImage: "pencil") }
            if let source = map.remoteURLString, let url = URL(string: source) {
                Link(destination: url) {
                    Label("Source: \(url.host() ?? "the web")", systemImage: "safari")
                }
            }
            Divider()
            Button(role: .destructive) { confirmingDelete = true } label: {
                Label("Delete Map…", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(dense ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Map actions")
    }

    /// In the side column there is no navigation bar to hang the map's name
    /// and actions on, so the pane carries its own row — the same picker and
    /// the same menu, one line high.
    private var paneHeader: some View {
        HStack(spacing: 8) {
            if maps.count > 1, placing == nil {
                Menu {
                    ForEach(maps) { m in
                        Button {
                            currentMapID = m.id; viewport?.wrappedValue = MapViewport(mapID: m.id)
                            zoom = 1; pan = .zero
                        } label: {
                            Label(m.name, systemImage: m.id == map?.id ? "checkmark" : "map")
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(map?.name ?? "Map").font(.subheadline.weight(.semibold))
                        Image(systemName: "chevron.down").font(.caption2)
                    }
                }
                .buttonStyle(.plain)
            } else {
                Text(map?.name ?? "Map").font(.subheadline.weight(.semibold))
            }
            Spacer()
            if placing != nil {
                Button("Cancel") { placing = nil }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
            } else if let map {
                mapMenu(map)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var fullScreen: some View {
        NavigationStack {
            workArea
            .navigationTitle(map?.name ?? "Map")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(.black.opacity(0.6), for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(placing == nil ? "Done" : "Cancel") {
                        if placing != nil { placing = nil } else { dismiss() }
                    }
                }
                if maps.count > 1, placing == nil {
                    ToolbarItem(placement: .principal) {
                        Menu {
                            ForEach(maps) { m in
                                Button {
                                    currentMapID = m.id; viewport?.wrappedValue = MapViewport(mapID: m.id)
                                    zoom = 1; pan = .zero
                                } label: {
                                    Label(m.name, systemImage: m.id == map?.id ? "checkmark" : "map")
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(map?.name ?? "Map").font(.headline)
                                Image(systemName: "chevron.down").font(.caption2)
                            }
                            .foregroundStyle(.white)
                        }
                    }
                }
                if placing == nil, let map {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button {
                                mapName = map.name; mapKind = map.kind; renaming = true
                            } label: { Label("Rename Map…", systemImage: "pencil") }
                            if let source = map.remoteURLString, let url = URL(string: source) {
                                Link(destination: url) {
                                    Label("Source: \(url.host() ?? "the web")", systemImage: "safari")
                                }
                            }
                            Divider()
                            Button(role: .destructive) { confirmingDelete = true } label: {
                                Label("Delete Map…", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle").foregroundStyle(.white)
                        }
                        .accessibilityLabel("Map actions")
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Canvas

    private func canvas(data: Data, pixel: CGSize) -> some View {
        GeometryReader { geo in
            let fitted = fit(pixel, in: geo.size)
            let index = categoryOfItem
            let counted = countedIDs
            let foundBefore = repo.markersFoundBefore(in: game, counted: counted)
            let scale = zoom * pinch
            let offset = CGSize(width: pan.width + drag.width, height: pan.height + drag.height)

            ZStack {
                if let image = PlatformImage(data: data) {
                    image.resizable().interpolation(.high)
                        .frame(width: fitted.width, height: fitted.height)
                }
                ForEach(visibleMarkers(index, counted)) { marker in
                    pin(marker, type: pinType(marker, index), counted: counted,
                        foundBefore: foundBefore.contains(marker.id))
                        .position(x: marker.normalizedX * fitted.width,
                                  y: marker.normalizedY * fitted.height)
                }
            }
            .frame(width: fitted.width, height: fitted.height)
            // On the content, before the transform: a gesture here reports
            // the map's own untransformed points, so zoom and pan need no
            // undoing. A zero-distance drag notes where the finger went
            // down; the long-press has no location and reads that.
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in lastTouch = value.startLocation }
            )
            // Pinning a list: a tap IS the pin, at the spot tapped. On the
            // content, so the location is already in map points.
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { value in pinForSession(at: value.location, fitted: fitted) }
            )
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.45)
                    .onEnded { _ in
                        // Not mid-list: there a press would drop a nameless,
                        // unlinked pin in among the ones the list is making.
                        guard placing == nil, session == nil, let point = lastTouch else { return }
                        drop(at: point, fitted: fitted)
                    }
            )
            .scaleEffect(scale)
            .offset(offset)
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(.rect)
            .gesture(
                MagnifyGesture()
                    .updating($pinch) { value, state, _ in state = value.magnification }
                    .onEnded { value in
                        zoom = min(max(zoom * value.magnification, 1), 8)
                        publish(pixel: pixel, fitted: fitted)
                    }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 4)
                    .updating($drag) { value, state, _ in state = value.translation }
                    .onEnded { value in
                        pan = CGSize(width: pan.width + value.translation.width,
                                     height: pan.height + value.translation.height)
                        publish(pixel: pixel, fitted: fitted)
                    }
            )
            .onTapGesture(count: 2) {
                // Mid-list a double tap is two quick pins' worth of tapping,
                // not a zoom; pinch still zooms.
                guard session == nil else { return }
                withAnimation(.snappy) {
                    if zoom > 1 { zoom = 1; pan = .zero } else { zoom = 2.5 }
                }
                publish(pixel: pixel, fitted: fitted)
            }
            // Arriving — expanded or put back — or the pane changing size as
            // the stage slides: take up the shared view instead of starting
            // fitted.
            .onAppear { adopt(pixel: pixel, fitted: fitted) }
            .onChange(of: geo.size) { _, _ in adopt(pixel: pixel, fitted: fitted) }
            .onChange(of: placing?.item?.id) { _, _ in }
            .overlay(alignment: .bottom) {
                if placing != nil {
                    Button {
                        placeAtCenter(fitted: fitted, container: geo.size)
                    } label: {
                        Label(placing?.moving != nil ? "Move here"
                              : placing?.item.map { "Place \"\($0.name)\" here" } ?? "Place here",
                              systemImage: "mappin")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(Capsule().fill(LSTheme.accentFill)
                                .shadow(color: LSTheme.accentStep, radius: 0, y: 3))
                            .foregroundStyle(LSTheme.onAccent)
                    }
                    .buttonStyle(.plain)
                    // Clear of the legend beneath it, which sits far closer
                    // to this button in a half-height pane than on a screen.
                    .padding(.bottom, embedded ? 64 + bottomInset : 130)
                }
            }
        }
    }

    /// Show what the other copy of this map was showing.
    private func adopt(pixel: CGSize, fitted: CGSize) {
        guard let shared = viewport?.wrappedValue,
              shared.mapID != nil, shared.mapID == map?.id else { return }
        let t = shared.transform(pixel: pixel, fitted: fitted)
        zoom = t.zoom
        pan = t.pan
    }

    /// Tell the other copy what this one is showing now.
    private func publish(pixel: CGSize, fitted: CGSize) {
        viewport?.wrappedValue = .captured(mapID: map?.id, zoom: zoom, pan: pan,
                                           pixel: pixel, fitted: fitted)
    }

    private func fit(_ pixel: CGSize, in container: CGSize) -> CGSize {
        let ratio = min(container.width / pixel.width, container.height / pixel.height)
        return CGSize(width: pixel.width * ratio, height: pixel.height * ratio)
    }

    /// The map point under the container's center: the transform is anchored
    /// at the center, so a content point p appears at center + p·scale + pan.
    private func placeAtCenter(fitted: CGSize, container: CGSize) {
        let s = zoom
        let p = CGPoint(x: -pan.width / s, y: -pan.height / s)
        let point = CGPoint(x: p.x + fitted.width / 2, y: p.y + fitted.height / 2)
        drop(at: point, fitted: fitted)
    }

    private func drop(at point: CGPoint, fitted: CGSize) {
        guard let map, fitted.width > 0, fitted.height > 0 else { return }
        let x = point.x / fitted.width, y = point.y / fitted.height
        guard (0...1).contains(x), (0...1).contains(y) else { return }
        if let moving = placing?.moving {
            repo.moveMarker(moving, x: x, y: y)
            placing = nil
            return
        }
        let item = placing?.item
        let marker = repo.addMarker(to: map, x: x, y: y,
                                    category: item == nil ? .note : .collectible,
                                    label: item?.name ?? "",
                                    linkedTrackerItemID: item?.id)
        placing = nil
        // A pin from an item is finished; a pin from a long-press wants a name.
        if item == nil { editing = marker }
    }

    // MARK: Pins

    /// A badge, not a colored teardrop: *"multiple pin icons for different
    /// things, not just colors"* (Tim, 09-08). The icon says what; the check
    /// replaces it once it's done.
    private func pin(_ marker: Marker, type: PinType, counted: Set<String>,
                     foundBefore: Bool = false) -> some View {
        let done = explored(marker, counted)
        // Found in an earlier playthrough and not this one: its own icon and
        // color still, ringed with dashes — somewhere you've been, to find again.
        let before = foundBefore && !done
        let scale = zoom * pinch
        return Button {
            editing = marker
        } label: {
            ZStack {
                Circle()
                    .fill(done ? Color.gray : type.color)
                    .overlay(Circle().strokeBorder(.white, style: StrokeStyle(lineWidth: 2, dash: before ? [3, 2] : [])))
                    .frame(width: 26, height: 26)
                Image(systemName: done ? "checkmark" : type.symbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
            .opacity(done ? 0.65 : 1)
            .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
            .frame(width: 44, height: 44)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        // Mid-list every tap on the map is a pin. A tap that also opened the
        // card of a pin under the finger would do two things at once.
        .allowsHitTesting(session == nil)
        // The pin keeps its size while the map zooms under it.
        .scaleEffect(1 / scale)
        .accessibilityLabel(marker.label.isEmpty ? type.label : "\(marker.label), \(type.label)")
        .accessibilityValue(done ? "Explored" : (before ? "Found in an earlier playthrough" : "Not yet"))
    }

    // MARK: Pinning a list

    private var session: PinSession? { pinning.map(\.wrappedValue) ?? localPinning }

    private func setSession(_ next: PinSession?) {
        if let pinning { pinning.wrappedValue = next } else { localPinning = next }
    }

    private var pinnableCategories: [TrackerCategoryDTO] {
        trackerCategories.filter { !$0.items.isEmpty && !$0.pending }
    }

    private func startPinning(_ categoryID: String) {
        placing = nil
        setSession(PinSession(categoryID: categoryID,
                              itemID: nextUnpinned(in: categoryID, after: nil)))
    }

    /// The list's items grouped by where they are, with the group this map
    /// is named after first — the "Forgotten Crossroads" in *"grubs -
    /// forgotten crossroads"*. Groups otherwise keep the order they were
    /// written in.
    private func pinningGroups(_ categoryID: String) -> [(heading: String?, items: [TrackerItemDTO])] {
        guard let category = trackerCategories.first(where: { $0.id == categoryID }) else { return [] }
        var order: [String?] = []
        var byHeading: [String?: [TrackerItemDTO]] = [:]
        for item in category.items {
            let trimmed = item.location?.trimmingCharacters(in: .whitespacesAndNewlines)
            let heading = (trimmed?.isEmpty ?? true) ? nil : trimmed
            if byHeading[heading] == nil { order.append(heading) }
            byHeading[heading, default: []].append(item)
        }
        var groups = order.map { (heading: $0, items: byHeading[$0] ?? []) }
        if let here = map?.name, !here.isEmpty,
           let hit = groups.firstIndex(where: { group in
               guard let heading = group.heading else { return false }
               return heading.localizedCaseInsensitiveContains(here)
                   || here.localizedCaseInsensitiveContains(heading)
           }), hit > 0 {
            groups.insert(groups.remove(at: hit), at: 0)
        }
        return groups
    }

    /// The next item with no pin anywhere on this game, after `after`,
    /// wrapping round — so skipping one and coming back to it works.
    private func nextUnpinned(in categoryID: String, after: String?) -> String? {
        let order = pinningGroups(categoryID).flatMap(\.items)
        guard !order.isEmpty else { return nil }
        let pinned = Set(repo.linkedMarkers(in: game).keys)
        let start = after.flatMap { id in order.firstIndex { $0.id == id } }.map { $0 + 1 } ?? 0
        for offset in 0..<order.count {
            let item = order[(start + offset) % order.count]
            if !pinned.contains(item.id) { return item.id }
        }
        return nil
    }

    private func pinForSession(at point: CGPoint, fitted: CGSize) {
        guard var current = session, let itemID = current.itemID, let map,
              fitted.width > 0, fitted.height > 0 else { return }
        let x = point.x / fitted.width, y = point.y / fitted.height
        guard (0...1).contains(x), (0...1).contains(y) else { return }
        if let last = lastSessionTap, Date.now.timeIntervalSince(last.at) < 0.4,
           hypot(last.point.x - point.x, last.point.y - point.y) < 12 { return }
        lastSessionTap = (point, .now)

        let item = categoryOfItem[itemID]?.items.first { $0.id == itemID }
        let marker = repo.addMarker(to: map, x: x, y: y, category: .collectible,
                                    label: item?.name ?? "", linkedTrackerItemID: itemID)
        current.lastPinID = marker.id
        // A counted item is many spots — "tap every location where a grub is"
        // when the grubs are one 0/46 row — so it stays selected for the next
        // tap. A checkbox item has its one spot now, so the list moves on.
        if (item?.countTarget ?? 0) <= 0 {
            current.itemID = nextUnpinned(in: current.categoryID, after: itemID)
        }
        setSession(current)
    }

    /// Takes the last pin back and puts its item up next again. The pin goes
    /// to Recently Deleted like any other, so even Undo can be undone.
    private func undoLastPin() {
        guard var current = session, let id = current.lastPinID,
              let marker = markers.first(where: { $0.id == id }) else { return }
        let itemID = marker.linkedTrackerItemID
        repo.deleteMarker(marker)
        current.lastPinID = nil
        current.itemID = itemID ?? current.itemID
        setSession(current)
    }

    /// The map, and — while a list is being pinned — that list beside it, or
    /// folded under it on a narrow screen.
    ///
    /// The canvas is the same child in every arrangement, so starting and
    /// finishing a list never throws away where you were looking.
    private var workArea: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= 640 && geo.size.height >= 520
            HStack(spacing: 0) {
                if let current = session, wide {
                    pinningPanel(current, compact: false)
                        .frame(width: min(320, geo.size.width * 0.36))
                    Divider()
                }
                canvasStack
                    .overlay(alignment: .bottom) {
                        if let current = session, !wide {
                            pinningPanel(current, compact: true)
                                .frame(maxHeight: current.minimized ? nil : geo.size.height * 0.45)
                                .clipShape(.rect(cornerRadius: 16))
                                .padding(.horizontal, 10)
                                .padding(.bottom, 10 + bottomInset)
                        }
                    }
            }
        }
    }

    private func pinningPanel(_ current: PinSession, compact: Bool) -> some View {
        let category = trackerCategories.first { $0.id == current.categoryID }
        let groups = pinningGroups(current.categoryID)
        let pinned = Set(repo.linkedMarkers(in: game).keys)
        let total = category?.items.count ?? 0
        let done = category?.items.filter { pinned.contains($0.id) }.count ?? 0
        let next = category?.items.first { $0.id == current.itemID }

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                // The moment you're most likely to be staring at a plain pin
                // is right here, so the icon itself opens the chooser.
                Button {
                    stylingCategory = category
                } label: {
                    Image(systemName: category.map(PinStyle.symbol(for:)) ?? PinStyle.fallback)
                        .foregroundStyle(LSTheme.accent)
                }
                .disabled(category == nil)
                .accessibilityLabel("Change the pin icon")
                VStack(alignment: .leading, spacing: 1) {
                    Text(category?.name ?? "Pinning")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text("\(done) of \(total) pinned")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if current.lastPinID != nil {
                    Button("Undo") { undoLastPin() }
                        .font(.caption.weight(.semibold))
                }
                if compact {
                    Button {
                        var folded = current
                        folded.minimized.toggle()
                        setSession(folded)
                    } label: {
                        Image(systemName: current.minimized ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.bold))
                    }
                    .accessibilityLabel(current.minimized ? "Show the list" : "Fold the list away")
                }
                Button("Done") { setSession(nil) }
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .tint(LSTheme.accent)
            .padding(12)

            Text(next.map { item in
                (item.countTarget ?? 0) > 0
                    ? "Tap every spot a “\(item.name)” is. Pick another item when you're done."
                    : "Tap the map where “\(item.name)” is."
            } ?? "Every item in this list has a pin.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            if !(compact && current.minimized) {
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                                if let heading = group.heading {
                                    Text(heading.uppercased())
                                        .font(.caption2.weight(.semibold))
                                        .kerning(0.5)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 8)
                                        .padding(.top, 10)
                                        .padding(.bottom, 2)
                                }
                                ForEach(group.items) { item in
                                    pinningRow(item, selected: item.id == current.itemID,
                                               pinned: pinned.contains(item.id))
                                        .id(item.id)
                                }
                            }
                        }
                        .padding(8)
                    }
                    // Keep the item up next in view as the list advances.
                    .onChange(of: current.itemID) { _, id in
                        guard let id else { return }
                        withAnimation { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
        }
        .background(.regularMaterial)
    }

    private func pinningRow(_ item: TrackerItemDTO, selected: Bool, pinned: Bool) -> some View {
        Button {
            guard var current = session else { return }
            current.itemID = item.id
            setSession(current)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: pinned ? "mappin.circle.fill" : "circle.dashed")
                    .foregroundStyle(pinned ? AnyShapeStyle(LSTheme.accent) : AnyShapeStyle(.tertiary))
                Text(item.name)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "hand.tap.fill")
                        .font(.caption)
                        .foregroundStyle(LSTheme.accent)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(selected ? LSTheme.accent.opacity(0.18) : .clear, in: .rect(cornerRadius: 8))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityValue(pinned ? "Pinned" : "Not pinned")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func color(_ category: MarkerCategory) -> Color {
        switch category {
        case .collectible: LSTheme.accent
        case .note:        .blue
        case .warning:     .red
        case .secret:      .purple
        }
    }

    private var crosshair: some View {
        ZStack {
            Circle().strokeBorder(LSTheme.accent, lineWidth: 2)
                .background(Circle().fill(LSTheme.accent.opacity(0.15)))
                .frame(width: 44, height: 44)
            Rectangle().fill(LSTheme.accent.opacity(0.7)).frame(width: 2, height: 70)
            Rectangle().fill(LSTheme.accent.opacity(0.7)).frame(width: 70, height: 2)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Toolbar

    private var toolbar: some View {
        VStack(spacing: 8) {
            if placing != nil {
                Text("Pan the map under the ring, then tap Place.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            } else {
                // Only the types that have pins on this map. Four chips reading
                // "Collectible 0 · Note 0 · Warning 0 · Secret 0" were a legend
                // for nothing, and with a tracker's categories as types the
                // full list could be twenty long.
                let entries = legend(categoryOfItem)
                if entries.isEmpty {
                    Text("No pins yet. Place one, or pin a list from the tracker.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(entries, id: \.type.id) { entry in
                                let off = hiddenTypes.contains(entry.type.id)
                                Button {
                                    if off { hiddenTypes.remove(entry.type.id) }
                                    else { hiddenTypes.insert(entry.type.id) }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: entry.type.symbol)
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(.white)
                                            .frame(width: 16, height: 16)
                                            .background(Circle().fill(entry.type.color))
                                        Text("\(entry.type.label) \(entry.count)")
                                            .font(.caption2)
                                            .strikethrough(off)
                                    }
                                    .foregroundStyle(off ? .white.opacity(0.4) : .white)
                                    .opacity(off ? 0.55 : 1)
                                }
                                .buttonStyle(.plain)
                                .lsTapTargetInline()
                                .accessibilityLabel("\(entry.type.label), \(entry.count)")
                                .accessibilityValue(off ? "Hidden" : "Shown")
                                .accessibilityHint("Toggles this type of pin")
                                .contextMenu {
                                    if let category = trackerCategories.first(where: {
                                        "cat:" + $0.id == entry.type.id
                                    }) {
                                        Button {
                                            stylingCategory = category
                                        } label: {
                                            Label("Pin Icon for \(category.name)…",
                                                  systemImage: entry.type.symbol)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }
                let counted = countedIDs
                HStack(spacing: 8) {
                    ForEach(Showing.allCases) { s in
                        let n: Int = switch s {
                        case .all:      markers.count
                        case .left:     markers.filter { !explored($0, counted) }.count
                        case .explored: markers.filter { explored($0, counted) }.count
                        }
                        Button {
                            showing = s
                        } label: {
                            Text(s == .all ? "All" : "\(s.label) (\(n))")
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(showing == s ? Color.white.opacity(0.18) : .clear, in: .capsule)
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    if !pinnableCategories.isEmpty, map != nil {
                        Menu {
                            let pinnedIDs = Set(repo.linkedMarkers(in: game).keys)
                            ForEach(pinnableCategories) { category in
                                let count = category.items.filter { pinnedIDs.contains($0.id) }.count
                                Button {
                                    startPinning(category.id)
                                } label: {
                                    Label("\(category.name) — \(count) of \(category.items.count)",
                                          systemImage: PinStyle.symbol(for: category))
                                }
                            }
                        } label: {
                            Label("Pin a List", systemImage: "list.bullet.below.rectangle")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(LSTheme.accent.opacity(0.22), in: .capsule)
                                .foregroundStyle(LSTheme.accent)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Pick a tracker category, then tap the map where each item is")
                    }
                    Button {
                        placing = Placing(item: nil)
                    } label: {
                        Label("Place", systemImage: "mappin")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(LSTheme.accent.opacity(0.22), in: .capsule)
                            .foregroundStyle(LSTheme.accent)
                    }
                    .buttonStyle(.plain)
                    .disabled(map == nil)
                }
            }
        }
        .padding(10)
        .background(.black.opacity(0.7), in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.12)))
        .padding(.horizontal, 12)
        .padding(.bottom, 12 + bottomInset)
    }
}
