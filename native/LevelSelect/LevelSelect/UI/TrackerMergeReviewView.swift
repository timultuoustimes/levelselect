import SwiftUI
import SwiftData

/// Review screen for a finished generation: what it would add, what it would
/// take away, and what it would rename — with nothing written until a choice is
/// made here.
///
/// This exists because regeneration was previously a leap of faith. You pressed
/// a button, waited two minutes, and either got something better or quietly
/// lost work, with no way to tell which until you went looking. The counts
/// below are the whole point.
struct TrackerMergeReviewView: View {
    @Bindable var game: Game
    let merge: PendingTrackerMerge
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// Incoming item ids the user wants. Starts as everything new, so the
    /// common "yes, add all of that" case is one tap.
    @State private var selected: Set<String> = []
    @State private var didPrime = false
    @State private var confirmingReplace = false

    @State private var generation = TrackerGenerationStore.shared

    private var diff: TrackerDiff { merge.diff }

    var body: some View {
        NavigationStack {
            List {
                summarySection
                if !diff.strandedByReplace.isEmpty { replaceWarning }
                ForEach(changedCategories) { category in
                    categorySection(category)
                }
                if diff.isEmpty { nothingChangedSection }
            }
            .navigationTitle("Review Changes")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        generation.discardPending(for: game.id)
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
        }
        .task {
            guard !didPrime else { return }
            didPrime = true
            selected = Set(diff.added.map(\.id))
        }
        .confirmationDialog("Replace the whole tracker?",
                            isPresented: $confirmingReplace, titleVisibility: .visible) {
            Button("Replace Everything", role: .destructive) { apply(.replace) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(replaceWarningText)
        }
    }

    // MARK: Sections

    private var summarySection: some View {
        Section {
            row("plus.circle.fill", .green, "\(diff.added.count) new",
                diff.added.isEmpty ? "Nothing this tracker doesn't already have"
                                   : "Items the current tracker is missing")
            if !diff.renamed.isEmpty {
                row("arrow.triangle.2.circlepath", LSTheme.accent,
                    "\(diff.renamed.count) renamed",
                    "Same items under new ids — your progress follows them")
            }
            if !diff.removed.isEmpty {
                row("minus.circle.fill", .orange, "\(diff.removed.count) missing",
                    "In your tracker, not in the new one. Only Replace drops these.")
            }
            if diff.unchangedCount > 0 {
                row("equal.circle.fill", .secondary, "\(diff.unchangedCount) unchanged", nil)
            }
        }
    }

    /// The sentence that does the work. A rename costs nothing now that ids are
    /// migrated, so this counts only what Replace would genuinely lose.
    private var replaceWarning: some View {
        Section {
            Label {
                Text(replaceWarningText)
                    .font(.caption)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }

    private var replaceWarningText: String {
        let lost = diff.removed.filter { d in diff.strandedByReplace.contains { $0.id == d.id } }
        guard !lost.isEmpty else {
            return "Replacing swaps the tracker content. Your progress follows anything that came back under a new name."
        }
        let names = lost.prefix(3).map(\.name).joined(separator: ", ")
        let more = lost.count > 3 ? " and \(lost.count - 3) more" : ""
        return "Replacing would drop \(lost.count) item\(lost.count == 1 ? "" : "s") you've already made progress on — \(names)\(more). You'll be offered to keep them as Personal Goals."
    }

    private var nothingChangedSection: some View {
        Section {
            Text("This generation came back with the same tracker you already have. Nothing to add.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var changedCategories: [TrackerCategoryDiff] {
        diff.categories.filter(\.hasChanges)
    }

    private func categorySection(_ category: TrackerCategoryDiff) -> some View {
        Section {
            ForEach(category.added) { item in
                Button {
                    if selected.contains(item.id) { selected.remove(item.id) }
                    else { selected.insert(item.id) }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: selected.contains(item.id)
                              ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected.contains(item.id) ? LSTheme.accent : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(.subheadline)
                            if let location = item.location, !location.isEmpty {
                                Text(location).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            // Shown but not selectable: these only matter if you pick Replace,
            // and then it's all of them.
            ForEach(category.removed) { item in
                HStack(spacing: 10) {
                    Image(systemName: "minus.circle").foregroundStyle(.orange)
                    Text(item.name).font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Text("Replace only").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            if !category.renamed.isEmpty {
                Text("\(category.renamed.count) renamed — progress follows")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Text(category.name)
                if category.isNewCategory {
                    Text("NEW")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(LSTheme.accent.opacity(0.2), in: .capsule)
                }
                Spacer()
                if !category.added.isEmpty {
                    Button(allSelected(in: category) ? "None" : "All") {
                        toggleAll(in: category)
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    /// Everything starts selected, so "Add 12" *is* add-all until you untick
    /// something — no separate control needed, and one primary action beats
    /// two that overlap. Replace sits beside it, deliberately quieter: it's
    /// the only choice here that can cost you anything.
    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button {
                apply(.add(itemIDs: selected))
            } label: {
                Label(selected.isEmpty ? "Nothing Selected" : "Add \(selected.count)",
                      systemImage: "plus.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(LSTheme.accent)
            .disabled(selected.isEmpty)

            Button(role: .destructive) {
                confirmingReplace = true
            } label: {
                Label("Replace", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    // MARK: Helpers

    private func row(_ icon: String, _ tint: Color,
                     _ title: String, _ subtitle: String?) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: icon).foregroundStyle(tint)
        }
    }

    private func allSelected(in category: TrackerCategoryDiff) -> Bool {
        !category.added.isEmpty && category.added.allSatisfy { selected.contains($0.id) }
    }

    private func toggleAll(in category: TrackerCategoryDiff) {
        if allSelected(in: category) {
            category.added.forEach { selected.remove($0.id) }
        } else {
            category.added.forEach { selected.insert($0.id) }
        }
    }

    private func apply(_ mode: TrackerMergeMode) {
        generation.applyPending(for: game, context: context, mode: mode)
        dismiss()
    }
}
