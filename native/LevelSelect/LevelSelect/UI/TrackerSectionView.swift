import SwiftUI
import SwiftData

/// Objective tracker: schema-driven checklist (categories → items) with
/// per-playthrough state. Personal Goals are user-added items in the same
/// schema. Everything syncs via CloudKit like the rest of the model.
struct TrackerSectionView: View {
    let game: Game
    @Environment(\.modelContext) private var context
    @State private var hideCompleted = false
    @State private var addingGoal = false
    @State private var goalName = ""
    @State private var expanded: Set<String> = []

    private var repo: Repository { Repository(context) }

    private var playthrough: Playthrough? {
        (game.playthroughs ?? []).first { $0.deletedAt == nil }
    }

    private var categories: [TrackerCategoryDTO] {
        guard let schema = game.trackerSchema else { return [] }
        return TrackerSchemaJSON.categories(from: schema.jsonData)
    }

    private var stateByItem: [String: TrackerStateRecord] {
        Dictionary(
            (playthrough?.trackerStates ?? [])
                .filter { $0.deletedAt == nil }
                .map { ($0.itemID, $0) },
            uniquingKeysWith: { a, _ in a }
        )
    }

    var body: some View {
        let cats = categories
        VStack(alignment: .leading, spacing: 12) {
            header(cats)

            if cats.isEmpty {
                Text("No tracker yet — add a personal goal to start one.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(cats) { category in
                    categoryView(category)
                }
            }

            Button {
                goalName = ""
                addingGoal = true
            } label: {
                Label("Add Personal Goal", systemImage: "plus.circle")
                    .font(.subheadline)
            }
            .buttonStyle(.borderless)
            .tint(LSTheme.purple)
        }
        .alert("New Personal Goal", isPresented: $addingGoal) {
            TextField("Goal", text: $goalName)
            Button("Add") {
                let trimmed = goalName.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                repo.addPersonalGoal(to: game, named: trimmed)
                expanded.insert(TrackerSchemaJSON.personalGoalsID)
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Header

    private func header(_ cats: [TrackerCategoryDTO]) -> some View {
        let allItems = cats.flatMap(\.items)
        let done = allItems.filter { stateByItem[$0.id]?.completed == true }.count
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer()
                if !allItems.isEmpty {
                    Text("\(done)/\(allItems.count)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Button {
                        hideCompleted.toggle()
                    } label: {
                        Image(systemName: hideCompleted ? "eye.slash.fill" : "eye")
                            .font(.subheadline)
                    }
                    .buttonStyle(.borderless)
                    .help("Hide completed")
                }
            }
            if !allItems.isEmpty {
                ProgressView(value: Double(done), total: Double(allItems.count))
                    .tint(LSTheme.purple)
            }
        }
    }

    // MARK: Category

    @ViewBuilder
    private func categoryView(_ category: TrackerCategoryDTO) -> some View {
        let visibleItems = hideCompleted
            ? category.items.filter { stateByItem[$0.id]?.completed != true }
            : category.items
        if !visibleItems.isEmpty {
            let done = category.items.filter { stateByItem[$0.id]?.completed == true }.count
            DisclosureGroup(isExpanded: expansionBinding(category.id)) {
                VStack(spacing: 2) {
                    ForEach(visibleItems) { item in
                        itemRow(item)
                    }
                }
                .padding(.top, 4)
            } label: {
                HStack {
                    Text(category.name)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(done)/\(category.items.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(done == category.items.count ? .green : .secondary)
                }
            }
            .tint(.secondary)
        }
    }

    private func expansionBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) },
            set: { open in
                if open { expanded.insert(id) } else { expanded.remove(id) }
            }
        )
    }

    // MARK: Item row

    @ViewBuilder
    private func itemRow(_ item: TrackerItemDTO) -> some View {
        let state = stateByItem[item.id]
        let done = state?.completed == true
        let hidden = item.hideUntilDiscovered && state?.revealed != true && !done

        HStack(alignment: .top, spacing: 10) {
            Button {
                let pt = repo.ensureDefaultPlaythrough(for: game)
                if hidden {
                    repo.revealTrackerItem(pt, itemID: item.id)
                } else {
                    repo.setTrackerItem(pt, itemID: item.id, done: !done)
                    repo.recomputeProgress(game)
                }
            } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(done ? AnyShapeStyle(LSTheme.purple) : AnyShapeStyle(.secondary))
                    .font(.body)
            }
            .buttonStyle(.borderless)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(hidden ? "Hidden — tap circle to reveal" : item.name)
                        .font(.subheadline)
                        .strikethrough(done, color: .secondary)
                        .foregroundStyle(hidden ? AnyShapeStyle(.tertiary) : (done ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary)))
                    if item.missable && !hidden {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .help("Missable")
                    }
                }
                if !hidden, let location = item.location {
                    Text(location)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !hidden, let maxRank = item.maxRank {
                    rankControl(item, maxRank: maxRank, current: state?.rank ?? 0)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(.rect)
        .padding(.vertical, 3)
    }

    private func rankControl(_ item: TrackerItemDTO, maxRank: Int, current: Int) -> some View {
        HStack(spacing: 8) {
            Stepper(value: Binding(
                get: { current },
                set: { newValue in
                    let pt = repo.ensureDefaultPlaythrough(for: game)
                    repo.setTrackerRank(pt, itemID: item.id, rank: min(newValue, maxRank), maxRank: maxRank)
                    repo.recomputeProgress(game)
                }
            ), in: 0...maxRank) {
                Text(rankLabel(item, current: current, maxRank: maxRank))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .controlSize(.mini)
        }
    }

    private func rankLabel(_ item: TrackerItemDTO, current: Int, maxRank: Int) -> String {
        if let names = item.rankNames, current > 0, current <= names.count {
            return names[current - 1]
        }
        return "\(current)/\(maxRank)"
    }
}
