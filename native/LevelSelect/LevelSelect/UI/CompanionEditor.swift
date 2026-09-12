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
    @Environment(\.modelContext) private var context

    /// People already recorded elsewhere in the library, minus whoever is
    /// already on this record. Typing "Rosalie" and her gamertag again every
    /// single co-op night is exactly the kind of chore the app shouldn't ask
    /// for when it already knows the answer.
    private var suggestions: [Companion] {
        let taken = Set(companions.map {
            $0.name.lowercased() + "|" + $0.handle.lowercased()
        })
        return Repository(context).knownCompanions()
            .filter { !taken.contains($0.name.lowercased() + "|" + $0.handle.lowercased()) }
            .prefix(8)
            .map { $0 }
    }

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

        if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(companions.isEmpty ? "Played with before" : "Also")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                FlowLayout(spacing: 6) {
                    ForEach(suggestions) { person in
                        Button {
                            // Name AND handle, so one tap records them the way
                            // they were recorded last time.
                            companions.append(Companion(name: person.name,
                                                        handle: person.handle))
                        } label: {
                            Label(person.display, systemImage: "plus")
                                .font(.caption)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(LSTheme.accent.opacity(0.16), in: .capsule)
                                .overlay(Capsule().strokeBorder(LSTheme.accent.opacity(0.4),
                                                                lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .tint(LSTheme.accent)
                    }
                }
            }
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
