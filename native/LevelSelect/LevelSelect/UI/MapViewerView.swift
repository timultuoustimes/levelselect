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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var currentMapID: UUID?
    @State private var hiddenKinds: Set<MarkerCategory> = []
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
        maps.first { $0.id == currentMapID } ?? target.map ?? maps.first
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

    private func explored(_ marker: Marker) -> Bool { repo.isExplored(marker, states: states) }

    private var visibleMarkers: [Marker] {
        markers.filter { m in
            !hiddenKinds.contains(m.category)
            && (showing == .all || (showing == .explored) == explored(m))
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
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
            .overlay(alignment: .bottom) { toolbar }
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
                                    currentMapID = m.id
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
            .sheet(item: $editing) { marker in
                MarkerCard(marker: marker, game: game) {
                    placing = Placing(item: nil, moving: marker)
                }
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
        }
        .onAppear {
            currentMapID = target.map?.id ?? maps.first?.id
            if let item = target.placingItem { placing = Placing(item: item) }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Canvas

    private func canvas(data: Data, pixel: CGSize) -> some View {
        GeometryReader { geo in
            let fitted = fit(pixel, in: geo.size)
            let scale = zoom * pinch
            let offset = CGSize(width: pan.width + drag.width, height: pan.height + drag.height)

            ZStack {
                if let image = PlatformImage(data: data) {
                    image.resizable().interpolation(.high)
                        .frame(width: fitted.width, height: fitted.height)
                }
                ForEach(visibleMarkers) { marker in
                    pin(marker)
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
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.45)
                    .onEnded { _ in
                        guard placing == nil, let point = lastTouch else { return }
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
                    .onEnded { value in zoom = min(max(zoom * value.magnification, 1), 8) }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 4)
                    .updating($drag) { value, state, _ in state = value.translation }
                    .onEnded { value in
                        pan = CGSize(width: pan.width + value.translation.width,
                                     height: pan.height + value.translation.height)
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation(.snappy) {
                    if zoom > 1 { zoom = 1; pan = .zero } else { zoom = 2.5 }
                }
            }
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
                    .padding(.bottom, 130)
                }
            }
        }
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

    private func pin(_ marker: Marker) -> some View {
        let done = explored(marker)
        let scale = zoom * pinch
        return Button {
            editing = marker
        } label: {
            ZStack {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 26))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, done ? Color.gray : color(marker.category))
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(.white)
                        .offset(y: -3)
                }
            }
            .opacity(done ? 0.6 : 1)
            .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
            .frame(width: 44, height: 44)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        // The pin keeps its size while the map zooms under it.
        .scaleEffect(1 / scale)
        .accessibilityLabel(marker.label.isEmpty ? marker.category.label : marker.label)
        .accessibilityValue(done ? "Explored" : "Not yet")
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
                HStack(spacing: 10) {
                    ForEach(MarkerCategory.allCases, id: \.self) { kind in
                        let count = markers.filter { $0.category == kind }.count
                        let off = hiddenKinds.contains(kind)
                        Button {
                            if off { hiddenKinds.remove(kind) } else { hiddenKinds.insert(kind) }
                        } label: {
                            HStack(spacing: 4) {
                                Circle().fill(color(kind)).frame(width: 8, height: 8)
                                Text("\(kind.label) \(count)")
                                    .font(.caption2)
                                    .strikethrough(off)
                            }
                            .foregroundStyle(off ? .white.opacity(0.4) : .white)
                        }
                        .buttonStyle(.plain)
                        .lsTapTargetInline()
                        .accessibilityLabel("\(kind.label), \(count)")
                        .accessibilityValue(off ? "Hidden" : "Shown")
                        .accessibilityHint("Toggles this kind of pin")
                    }
                }
                HStack(spacing: 8) {
                    ForEach(Showing.allCases) { s in
                        let n: Int = switch s {
                        case .all:      markers.count
                        case .left:     markers.filter { !explored($0) }.count
                        case .explored: markers.filter(explored).count
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
        .padding(.bottom, 12)
    }
}
