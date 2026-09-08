import SwiftUI
import SwiftData

/// Which ownership and access chips this library uses.
///
/// "Ownership & access", not "Ownership chips": four of the nine words are
/// not ownership at all — Subscription, Rented, Borrowed, Shared and Arcade
/// are ways you *reach* a game — and the row title should not argue with the
/// chips under it. Tim, build 37 brief: *"ownership & access chips."*
///
/// Ownership is the one vocabulary in the app that is genuinely
/// person-specific. A PC-only library has no use for Physical; somebody
/// cataloguing a childhood has every use for Rented and none for Subscription.
/// Tim, arriving at it from a memory of a Halo 2 he never owned: *"maybe we
/// let them choose what ownership options they want displayed?"*
///
/// **Hiding one never changes a game.** A game already marked with a hidden
/// chip keeps the mark and keeps showing it — see `OwnershipControl`. Turning
/// a chip off is a decision about what you want to think about, not an edit to
/// your library, and the footer says so because a screen full of switches
/// beside the word "ownership" invites the other reading.
struct OwnershipChipsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ThemeSettings.createdAt) private var themeSettings: [ThemeSettings]

    private var settings: ThemeSettings? { themeSettings.first }
    private var chosen: [Ownership] {
        ThemePalette.chips(from: settings?.ownershipChipsRaw)
    }
    private var order: OwnershipChipOrder {
        ThemePalette.chipOrder(from: settings?.ownershipChipsRaw)
    }

    var body: some View {
        page
            // The counts are pushed in from Home, which may not have been
            // visited this launch. One fetch when this page opens is what
            // makes the "Most used" preview below tell the truth.
            .task { ThemePalette.refreshOwnershipUsage(
                from: (try? context.fetch(FetchDescriptor<Game>())) ?? []) }
    }

    private var page: some View {
        SettingsPage(title: "Ownership & access",
                     icon: "shippingbox",
                     blurb: "How you have each game. Turn off the ones your library never uses.") {
            Section {
                ForEach(Ownership.allCases, id: \.self) { kind in
                    Toggle(isOn: binding(for: kind)) {
                        Label(kind.label, systemImage: kind.systemImage)
                    }
                    .tint(LSTheme.accent)
                }
            } footer: {
                Text("Turning one off only hides it. A game already marked with it keeps the mark, and keeps showing it, so nothing you recorded is lost. Syncs to your other devices.")
            }

            Section {
                Picker("Order", selection: Binding(
                    get: { order },
                    set: { write(chips: reordered(for: $0), order: $0) })) {
                    ForEach(OwnershipChipOrder.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                preview
            } header: {
                Text("Order")
            } footer: {
                Text(order.blurb)
            }

            if chosen.count == 1 {
                Section {
                    Label("One chip left. Turning off the last one puts all six back — a game page with no way to say you own the game isn't a state worth having.",
                          systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// What the row will actually look like, which `Most used` needs: it is
    /// the one order you cannot work out by reading the list above.
    ///
    /// **In Custom, the chips themselves are the arranger.** Each one grows a
    /// grip and can be dragged onto another to take its place — the order is
    /// edited where it is seen, rather than in a second list below. Tim,
    /// 09-08: *"custom order button for ownership & access should add the
    /// grips to the different ones in place, instead of opening a new
    /// reordering thing below it."*
    private var preview: some View {
        ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 6) {
            ForEach(chosen, id: \.self) { kind in
                chip(kind)
            }
        }
        .foregroundStyle(.secondary)
        .padding(.vertical, 2)
        }
        .accessibilityElement(children: order == .custom ? .contain : .combine)
        .accessibilityLabel("Preview: " + chosen.map(\.label).joined(separator: ", "))
    }

    @ViewBuilder
    private func chip(_ kind: Ownership) -> some View {
        let label = HStack(spacing: 4) {
            if order == .custom {
                Image(systemName: "line.3.horizontal")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            Image(systemName: kind.systemImage)
            Text(kind.label)
        }
        .font(.caption2.weight(.medium))
        .lineLimit(1)
        .padding(.horizontal, 7).padding(.vertical, 4)
        .background(LSTheme.cardFill, in: .capsule)
        .overlay(Capsule().strokeBorder(LSTheme.hairline, lineWidth: 1))

        if order == .custom {
            label
                .draggable(kind.rawValue)
                .dropDestination(for: String.self) { dropped, _ in
                    guard let raw = dropped.first, let moved = Ownership(rawValue: raw),
                          moved != kind,
                          let from = chosen.firstIndex(of: moved),
                          let to = chosen.firstIndex(of: kind) else { return false }
                    var list = chosen
                    list.remove(at: from)
                    list.insert(moved, at: to)
                    write(chips: list, order: .custom)
                    return true
                }
                .accessibilityHint("Drag onto another chip to take its place")
        } else {
            label
        }
    }

    private func binding(for kind: Ownership) -> Binding<Bool> {
        Binding(
            get: { chosen.contains(kind) },
            set: { on in
                var next = Set(chosen)
                if on { next.insert(kind) } else { next.remove(kind) }
                // Custom keeps what you arranged and puts a newly shown chip on
                // the end; the other two orders are derived, so they are always
                // written in `allCases` order — two devices choosing the same
                // set then store the same string.
                let list: [Ownership] = order == .custom
                    ? chosen.filter(next.contains)
                        + Ownership.allCases.filter { next.contains($0) && !chosen.contains($0) }
                    : Ownership.allCases.filter(next.contains)
                write(chips: list, order: order)
            })
    }

    /// Switching modes rewrites the stored list in that mode's own order, so
    /// the string always says what the row is doing.
    private func reordered(for next: OwnershipChipOrder) -> [Ownership] {
        switch next {
        case .standard, .mostUsed: Ownership.allCases.filter(Set(chosen).contains)
        // Custom starts from whatever you were just looking at, rather than
        // snapping back to the app's order the moment you choose it.
        case .custom: chosen
        }
    }

    private func write(chips: [Ownership], order: OwnershipChipOrder) {
        let settings = ThemePalette.fetchOrCreate(in: context)
        var parts: [String] = []
        if let token = order.storedToken { parts.append(token) }
        parts += chips.map(\.rawValue)
        settings.ownershipChipsRaw = parts.joined(separator: ",")
        settings.updatedAt = .now
        ThemePalette.refresh(from: settings)
    }
}
