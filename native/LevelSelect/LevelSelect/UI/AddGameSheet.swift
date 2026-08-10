import SwiftUI

struct AddGameSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @AppStorage("lastPlatform") private var lastPlatform = ""
    @AppStorage("lastStatusRaw") private var lastStatusRaw = GameStatus.playing.rawValue

    @State private var name = ""
    @State private var platform = ""
    @State private var status: GameStatus = .playing

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Platform", text: $platform)
                    Picker("Status", selection: $status) {
                        ForEach(GameStatus.allCases, id: \.self) { s in
                            Text(s.label).tag(s)
                        }
                    }
                }
            }
            .navigationTitle("Add Game")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: add)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                platform = lastPlatform
                status = GameStatus(rawValue: lastStatusRaw) ?? .playing
            }
        }
    }

    private func add() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let repo = Repository(context)
        let game = repo.addGame(name: trimmed, status: status)
        let p = platform.trimmingCharacters(in: .whitespaces)
        if !p.isEmpty {
            game.platforms = [p]
            lastPlatform = p
        }
        lastStatusRaw = status.rawValue
        dismiss()
    }
}
