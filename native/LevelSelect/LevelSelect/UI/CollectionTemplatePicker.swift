import SwiftUI
import SwiftData

/// Start a collection from a question rather than a blank name field.
///
/// "New Collection" asks you to have already had the idea. These supply the
/// idea — and the count, which is the part that turns it into a decision.
struct CollectionTemplatePicker: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<Game> { $0.deletedAt == nil })
    private var games: [Game]

    /// Handed back so the caller can open what was just made — a list that
    /// appears somewhere off-screen feels like nothing happened.
    var onCreate: (GameCollection) -> Void = { _ in }

    /// Whether the seeded templates start with a draft or empty.
    ///
    /// Remembered, because it's a working preference rather than a per-list
    /// decision. Some of these prompts genuinely want to be answered by hand —
    /// "Let's Be Real" is a confession, and a list the app wrote for you isn't
    /// one. Undoing a draft you didn't want is worse than never getting it, so
    /// the choice is offered before rather than after.
    @AppStorage("collectionTemplatePrefill") private var prefill = true

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Pick a question. The number is a prompt, not a limit — it's there to make you choose.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle(isOn: $prefill) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Start with suggestions").font(.subheadline)
                            Text("Some prompts can answer themselves from your library. Either way you can add and remove freely afterwards.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(LSTheme.accent)
                }
                ForEach(CollectionTemplate.grouped(), id: \.group) { section in
                    Section(section.group.rawValue) {
                        ForEach(section.templates) { template in
                            Button { create(template) } label: { row(template) }
                        }
                    }
                }
            }
            .navigationTitle("Start a Collection")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func row(_ template: CollectionTemplate) -> some View {
        let seeded = prefill ? seedCount(template) : 0
        return HStack(spacing: 12) {
            Image(systemName: template.systemImage)
                .font(.title3)
                .foregroundStyle(LSTheme.accent)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(template.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(template.prompt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // Only ever advertised when there is something to start from.
                // "Starts with 0 from your library" would be a worse promise
                // than making none.
                if seeded > 0 {
                    Text("Starts with \(seeded) from your library")
                        .font(.caption2)
                        .foregroundStyle(LSTheme.accent.opacity(0.9))
                }
            }
            Spacer(minLength: 8)
            Text("\(template.slots)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.white.opacity(0.06), in: .capsule)
        }
    }

    private func seedCount(_ template: CollectionTemplate) -> Int {
        template.seed.map {
            CollectionSeeding.games(for: $0, from: games, limit: template.slots).count
        } ?? 0
    }

    private func create(_ template: CollectionTemplate) {
        let picks = (prefill ? template.seed : nil).map {
            CollectionSeeding.games(for: $0, from: games, limit: template.slots)
        } ?? []
        let collection = Repository(context).createCollection(from: template, seededWith: picks)
        onCreate(collection)
        dismiss()
    }
}
