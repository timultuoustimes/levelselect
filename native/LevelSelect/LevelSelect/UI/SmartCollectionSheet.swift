import SwiftUI
import SwiftData

/// "Save these filters as a collection" — the whole front door for a Smart
/// Collection. The filters you already set are the rule; this asks only
/// for a name and whether it belongs on Home.
struct SaveSmartCollectionSheet: View {
    let rule: SmartCollectionRule
    let matching: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var showOnHome = true

    private var repo: Repository { Repository(context) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    FlowLayout(spacing: 6) {
                        ForEach(rule.describe(statusName: { $0.sectionTitle }), id: \.self) { word in
                            Text(word)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(LSTheme.accent.opacity(0.16), in: .capsule)
                                .foregroundStyle(LSTheme.accent)
                        }
                    }
                } footer: {
                    Text("\(Format.gameCount(matching)) match right now. A smart collection fills itself: add a game that fits and it's in; change the game and it may leave.")
                }
                Section {
                    Toggle("Show on Home", isOn: $showOnHome).tint(LSTheme.accent)
                } footer: {
                    Text("As its own shelf, under its name. You can move it in Arrange Home.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Save as a collection")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let collection = repo.createSmartCollection(name: name, rule: rule)
                        if showOnHome {
                            let settings = ThemePalette.fetchOrCreate(in: context)
                            var layout = HomeLayout.resolve(raw: settings.homeLayoutRaw)
                            layout.pin(collection: collection.id)
                            settings.homeLayoutRaw = layout.raw
                            settings.updatedAt = .now
                        }
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear { name = rule.describe(statusName: { $0.sectionTitle }).joined(separator: " · ") }
    }
}
