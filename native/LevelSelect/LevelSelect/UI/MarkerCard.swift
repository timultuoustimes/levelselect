import SwiftUI
import SwiftData

/// One pin: what it is, what it's for, and whether you've been.
///
/// Linking to a tracker item hands the pin its name and its state — the
/// checkbox here IS the item's checkbox, and the card says so. Unlink and
/// the pin keeps its own "Explored" stamp again.
struct MarkerCard: View {
    let marker: Marker
    let game: Game
    /// Asked to move this pin: the viewer enters place mode with it in hand.
    var onMove: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var label = ""
    @State private var category: MarkerCategory = .note
    @State private var notes = ""
    @State private var linkedID: String?
    @State private var choosingItem = false
    @State private var confirmingDelete = false

    private var repo: Repository { Repository(context) }

    private var categories: [TrackerCategoryDTO] {
        game.trackerSchema.map { TrackerSchemaJSON.categories(from: $0.jsonData) } ?? []
    }
    private var linkedItem: TrackerItemDTO? {
        guard let linkedID else { return nil }
        for cat in categories { if let item = cat.items.first(where: { $0.id == linkedID }) { return item } }
        return nil
    }
    private var states: [String: TrackerStateRecord] {
        let pt = game.activePlaythrough
        return Dictionary((pt?.trackerStates ?? []).filter { $0.deletedAt == nil }.map { ($0.itemID, $0) },
                          uniquingKeysWith: { a, _ in a })
    }

    /// Found in another playthrough and not this one.
    private var foundBefore: Bool {
        let counted: Set<String> = (linkedItem?.countTarget ?? 0) > 0 ? Set([linkedID].compactMap { $0 }) : []
        return repo.markersFoundBefore(in: game, counted: counted).contains(marker.id)
    }

    private var exploredBinding: Binding<Bool> {
        Binding(
            get: {
                // A counted item's pin is one spot of many, so it keeps its
                // own stamp — the same rule as `MapsRepository.isExplored`.
                if let linkedID, (linkedItem?.countTarget ?? 0) <= 0 {
                    return states[linkedID]?.completed ?? false
                }
                // Found in this playthrough, not the game (`pinStateID`).
                return states[repo.pinStateID(marker)]?.completed ?? false
            },
            set: { on in
                save()
                repo.setExplored(marker, on, in: game)
            })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let item = linkedItem {
                        LabeledContent("Tracker item") {
                            Text(item.name).foregroundStyle(.primary)
                        }
                        Button {
                            choosingItem = true
                        } label: { Label("Change item…", systemImage: "link") }
                        Button(role: .destructive) {
                            linkedID = nil
                            if label.isEmpty { label = item.name }
                        } label: { Label("Unlink", systemImage: "link.badge.plus") }
                    } else {
                        TextField("Label", text: $label)
                        if !categories.isEmpty {
                            Button {
                                choosingItem = true
                            } label: { Label("Link to a tracker item…", systemImage: "link") }
                        }
                    }
                    Picker("Kind", selection: $category) {
                        ForEach(MarkerCategory.allCases, id: \.self) { kind in
                            Label(kind.label, systemImage: kind.systemImage).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    if linkedItem != nil {
                        Text("Checking either one checks the other. The pin shows the item's name and its state.")
                    }
                }

                Section {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }

                Section {
                    Toggle(isOn: exploredBinding) {
                        Label(linkedItem == nil ? "Explored"
                              : ((linkedItem?.countTarget ?? 0) > 0 ? "Found here" : "Done"),
                              systemImage: "checkmark.circle")
                    }
                    .tint(LSTheme.accent)
                } footer: {
                    if foundBefore && !exploredBinding.wrappedValue {
                        Text("Found in an earlier playthrough. Mark it here when you find it again.")
                    }
                }

                Section {
                    if let onMove {
                        // Tim, 09-08: *"I need to be able to move a location pin."*
                        Button { save(); onMove(); dismiss() } label: {
                            Label("Move Pin", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                        }
                    }
                    Button(role: .destructive) { confirmingDelete = true } label: {
                        Label("Delete Pin", systemImage: "trash")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(linkedItem?.name ?? (label.isEmpty ? "Pin" : label))
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save(); dismiss() }
                }
            }
            .sheet(isPresented: $choosingItem) {
                TrackerItemPicker(categories: categories, selected: linkedID) { id in
                    linkedID = id
                    choosingItem = false
                }
                .lsSheet()
            }
            .confirmationDialog("Delete this pin?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete Pin", role: .destructive) {
                    repo.deleteMarker(marker)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .onAppear {
            label = marker.label
            category = marker.category
            notes = marker.notes ?? ""
            linkedID = marker.linkedTrackerItemID
        }
    }

    private func save() {
        repo.updateMarker(marker,
                          label: linkedItem?.name ?? label,
                          category: category,
                          notes: notes,
                          linkedTrackerItemID: linkedID)
    }
}

/// Every item in the tracker, by category, one tap to link.
struct TrackerItemPicker: View {
    let categories: [TrackerCategoryDTO]
    let selected: String?
    var onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(categories) { cat in
                    let items = cat.items.filter {
                        query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)
                    }
                    if !items.isEmpty {
                        Section(cat.name) {
                            ForEach(items) { item in
                                Button { onPick(item.id) } label: {
                                    HStack {
                                        Text(item.name)
                                        if let loc = item.location, !loc.isEmpty {
                                            Text("· \(loc)").foregroundStyle(.secondary).font(.caption)
                                        }
                                        Spacer()
                                        if item.id == selected {
                                            Image(systemName: "checkmark").foregroundStyle(LSTheme.accent)
                                        }
                                    }
                                }
                                .tint(.primary)
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Find an item")
            .navigationTitle("Link to item")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}
