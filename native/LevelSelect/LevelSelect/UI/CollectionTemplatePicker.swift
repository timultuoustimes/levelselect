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

    /// The card's height grows with the reader's text size instead of being a
    /// fixed 152pt. A card is a box with four lines of scaling text in it, so
    /// pinning its height means clipping the prompt at accessibility sizes —
    /// the same failure as an action row that hyphenates rather than wraps.
    @ScaledMetric(relativeTo: .subheadline) private var cardHeight: CGFloat = 152

    /// Scales too, so accessibility sizes get fewer, WIDER cards rather than
    /// the same narrow columns with more clipped text in them. Capped so a
    /// huge text size doesn't collapse the grid to one giant column on iPad.
    @ScaledMetric(relativeTo: .subheadline) private var columnWidth: CGFloat = 158

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: min(columnWidth, 300)), spacing: 12)]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    ForEach(CollectionTemplate.grouped(), id: \.group) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(section.group.rawValue)
                                .font(.title3.bold())
                                .padding(.horizontal)
                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(section.templates) { template in
                                    Button { create(template) } label: { card(template) }
                                        .buttonStyle(PressableCardStyle())
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical)
            }
            .scrollIndicators(.hidden)
            .lsBackground()
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pick a question. The number is a prompt, not a limit — it's there to make you choose.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Toggle(isOn: $prefill) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start with suggestions").font(.subheadline)
                    Text("Some prompts can answer themselves from your library. Either way, you can add and remove freely afterwards.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(LSTheme.accent)
        }
        .padding(.horizontal)
    }

    /// A card rather than a list row.
    ///
    /// These are meant to be browsed and picked from, and twenty-seven gray
    /// rows read as a settings screen. The color comes from the section, so
    /// the page has places in it rather than one wall of identical lines.
    private func card(_ template: CollectionTemplate) -> some View {
        let rgb = template.group.tint
        let tint = Color(red: rgb.r, green: rgb.g, blue: rgb.b)
        let seeded = prefill ? seedCount(template) : 0
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Image(systemName: template.systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .shadow(color: tint.opacity(0.6), radius: 6)
                Spacer(minLength: 4)
                Text("\(template.slots)")
                    .font(.caption.monospacedDigit().weight(.heavy))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(.black.opacity(0.28), in: .capsule)
            }
            Spacer(minLength: 0)
            Text(template.name)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
            Text(template.prompt)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.78))
                // No cap. The prompt IS the card; growing the box while still
                // ellipsizing at three lines meant the extra height revealed
                // nothing, and "Let's Be Real" lost the premise that makes it
                // work. Scaling a container is not a fix if its contents are
                // still capped.
                .multilineTextAlignment(.leading)
            if seeded > 0 {
                Label("\(seeded) to start", systemImage: "wand.and.stars")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(.black.opacity(0.28), in: .capsule)
            }
        }
        .padding(12)
        // minHeight, not height: the grid sizes each row to its tallest card,
        // so a long prompt at a large text size grows the row instead of
        // losing its last line.
        .frame(minHeight: cardHeight, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [tint.opacity(0.95), tint.opacity(0.55)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .strokeBorder(.white.opacity(0.14), lineWidth: 1))
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
