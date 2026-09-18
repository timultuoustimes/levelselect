import SwiftUI
import SwiftData

/// "What's this tracker for?" — asked before a plan, so someone who wants
/// the story gets the story and not fourteen lists.
struct TrackerShapeView: View {
    @Bindable var game: Game
    /// A playthrough the planned lists become the focus of.
    var focusing: Playthrough? = nil
    /// Called once the plan has started.
    var onStarted: () -> Void

    @Environment(\.modelContext) private var context
    @State private var chosen: [TrackerShape] = []
    @State private var generation = TrackerGenerationStore.shared

    private var offered: [TrackerShape] {
        TrackerShape.offered(genres: game.genres, themes: game.themes,
                             hasRuns: Repository(context).runTrackingEnabled(for: game))
    }

    var body: some View {
        Form {
            Section {
                ForEach(offered) { shape in
                    Button {
                        toggle(shape)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: shape.systemImage)
                                .font(.title3)
                                .foregroundStyle(LSTheme.accent)
                                .frame(width: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(shape.label).foregroundStyle(.primary)
                                Text(shape.blurb)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if chosen.contains(shape) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(LSTheme.accent)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(chosen.contains(shape) ? .isSelected : [])
                }
            } header: {
                Text("What's this tracker for?")
            } footer: {
                Text("Pick one or two. The plan stays inside what you choose, and you can plan more later.")
            }

            Section {
                Button {
                    plan(chosen)
                } label: {
                    Label(chosen.isEmpty ? "Plan" : "Plan \(chosen.map(\.label).joined(separator: " + "))",
                          systemImage: "list.bullet.rectangle.portrait")
                }
                .disabled(chosen.isEmpty || generation.isGenerating(game.id))
                Button("Let the Planner Decide") { plan([]) }
                    .disabled(generation.isGenerating(game.id))
            }
        }
        .lsFormStyle()
        .navigationTitle("Plan a Tracker")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func toggle(_ shape: TrackerShape) {
        if let i = chosen.firstIndex(of: shape) {
            chosen.remove(at: i)
        } else if chosen.count < 3 {
            chosen.append(shape)
        }
    }

    private func plan(_ shapes: [TrackerShape]) {
        generation.suggestCategories(for: game, context: context, shapes: shapes, focusing: focusing)
        onStarted()
    }
}

/// The shape question as its own sheet, from the tracker's Plan buttons.
struct TrackerShapeSheet: View {
    @Bindable var game: Game
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TrackerShapeView(game: game) { dismiss() }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
    }
}
