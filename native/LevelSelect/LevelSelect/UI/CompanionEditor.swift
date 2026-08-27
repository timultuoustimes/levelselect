import SwiftUI

/// Who you played with — as many people as were there, each with a name, a
/// handle, or both.
///
/// Two fields per person rather than one, because co-op spans a couch and a
/// voice channel: "Rosalie" is who she is, "@umigame" is who she is on the
/// Switch, and which you'd reach for depends on the game. One field would
/// make the other unrecordable.
struct CompanionEditor: View {
    @Binding var companions: [Companion]

    var body: some View {
        ForEach($companions) { $companion in
            VStack(spacing: 6) {
                TextField("Name", text: $companion.name)
                    #if !os(macOS)
                    .textInputAutocapitalization(.words)
                    #endif
                TextField("Gamertag or username", text: $companion.handle)
                    .autocorrectionDisabled()
                    #if !os(macOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .foregroundStyle(.secondary)
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    companions.removeAll { $0.id == companion.id }
                } label: { Label("Remove", systemImage: "trash") }
            }
        }

        Button {
            companions.append(Companion())
        } label: {
            Label(companions.isEmpty ? "Add someone" : "Add another",
                  systemImage: "person.badge.plus")
        }
    }
}

/// The read-only version: one line, for a row that has to stay one line.
struct CompanionLine: View {
    let companions: [Companion]
    var body: some View {
        if !companions.isEmpty {
            Label(companions.sentence, systemImage: companions.count > 1
                  ? "person.2.fill" : "person.fill")
                .font(.caption)
                .foregroundStyle(LSTheme.accent.opacity(0.9))
                .lineLimit(1)
        }
    }
}
