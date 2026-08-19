import SwiftUI
import SwiftData

/// What's being edited. Carried as a value so the sheet opens already filled in.
struct EditTarget: Identifiable, Hashable {
    var categoryID: String
    var itemID: String
    var name: String
    var location: String
    var note: String
    /// Present when the item is already a counter, so the sheet opens with
    /// its total rather than looking unset.
    var countTarget: Int? = nil

    var id: String { "\(categoryID)/\(itemID)" }
}

/// Edit one tracker item: its name, where it is, and your own note about it.
///
/// A sheet rather than an alert because an alert's single-line field is
/// unusable for anything longer than a couple of words — and a note is exactly
/// the thing you want room for.
struct TrackerItemEditView: View {
    @Bindable var game: Game
    let target: EditTarget
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var location = ""
    @State private var note = ""
    @State private var countTarget = ""
    @State private var primed = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Name", text: $name, axis: .vertical)
                        .lineLimit(1...4)
                }
                Section("Location") {
                    TextField("Where to find it", text: $location, axis: .vertical)
                        .lineLimit(1...3)
                }
                Section {
                    HStack {
                        TextField("None", text: $countTarget)
                            #if !os(macOS)
                            .keyboardType(.numberPad)
                            #endif
                        Text("to collect")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Count")
                } footer: {
                    // The row that makes 900 koroks a single line instead of
                    // an unusable wall.
                    Text("Give this a number and the row becomes a counter — tap to add one as you find them, and it ticks itself off when you reach the total. Leave it empty for a plain checkbox.")
                }

                Section {
                    TextField("Anything you want to remember", text: $note, axis: .vertical)
                        .lineLimit(3...12)
                } header: {
                    Text("Your Note")
                } footer: {
                    // The distinction that keeps regeneration safe, said plainly
                    // where someone is about to rely on it.
                    Text("Your note is yours — regenerating this tracker won't touch it. The item's own description can be replaced.")
                }
            }
            .navigationTitle("Edit Item")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .task {
            guard !primed else { return }
            primed = true
            name = target.name
            location = target.location
            note = target.note
            countTarget = target.countTarget.map(String.init) ?? ""
        }
    }

    private func save() {
        let repo = Repository(context)
        repo.editTrackerItem(
            game, categoryID: target.categoryID, itemID: target.itemID,
            name: name, location: location, note: note)
        // Separate from the text edits: an empty field means "not a counter",
        // which has to clear the key rather than leave the old total behind.
        let parsed = Int(countTarget.trimmingCharacters(in: .whitespaces))
        if parsed != target.countTarget {
            repo.setTrackerCountTarget(game, categoryID: target.categoryID,
                                       itemID: target.itemID, target: parsed)
        }
        dismiss()
    }
}
