import SwiftUI
import SwiftData

/// What a run records — the loadout picked before it, the score or time
/// after it, and the list it fills along the way.
///
/// Until 2026-09-17 a run's fields came only from a built-in or generated
/// tracker, so a speedrunner couldn't add a time and a Balatro player
/// couldn't add jokers. Fields keep their ids through edits, so a run that
/// recorded one keeps the value.
struct RunFieldsEditorSheet: View {
    @Bindable var game: Game
    let template: RunTemplateDTO
    var categories: [TrackerCategoryDTO] = []
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    struct Draft: Identifiable, Equatable {
        var id: String
        var label: String
        var kind: Kind
        var options: String = ""
        var optionsFrom: String = ""
        var after = false
        var best: String = ""
        /// Settings the editor doesn't show, carried through untouched.
        var onlyUnlocked = false
        var dependsOn: String?

        enum Kind: String, CaseIterable, Identifiable {
            case text, select, multi, number, time, list
            var id: String { rawValue }
            var label: String {
                switch self {
                case .text: "Text"
                case .select: "Choice"
                case .multi: "Several choices"
                case .number: "Number"
                case .time: "Time"
                case .list: "List during the run"
                }
            }
            var hasOptions: Bool { self == .select || self == .multi || self == .list }
            var isNumeric: Bool { self == .number || self == .time }
        }

        init(id: String, label: String, kind: Kind) {
            self.id = id
            self.label = label
            self.kind = kind
        }

        init(_ field: RunFieldDTO) {
            id = field.id
            label = field.label
            kind = Kind(rawValue: field.kind) ?? .text
            options = field.options.joined(separator: ", ")
            optionsFrom = field.optionsFrom ?? ""
            after = field.isEndPhase
            best = field.best ?? ""
            onlyUnlocked = field.onlyUnlocked
            dependsOn = field.dependsOn
        }

        var field: RunFieldDTO {
            let list = options.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            return RunFieldDTO(
                id: id,
                label: label.trimmingCharacters(in: .whitespacesAndNewlines),
                kind: kind.rawValue,
                options: kind.hasOptions && optionsFrom.isEmpty ? list : [],
                optionsFrom: kind.hasOptions && !optionsFrom.isEmpty ? optionsFrom : nil,
                onlyUnlocked: onlyUnlocked,
                dependsOn: dependsOn,
                phase: kind == .list ? "during" : (after ? "end" : "start"),
                best: kind.isNumeric && !best.isEmpty ? best : nil)
        }
    }

    @State private var drafts: [Draft] = []
    @State private var primed = false
    @State private var suggesting = false
    @State private var suggestion: String?

    private var repo: Repository { Repository(context) }

    var body: some View {
        NavigationStack {
            Form {
                ForEach($drafts) { $draft in
                    Section {
                        TextField("Name", text: $draft.label)
                            .font(.body.weight(.medium))
                        Picker("Kind", selection: $draft.kind) {
                            ForEach(Draft.Kind.allCases) { Text($0.label).tag($0) }
                        }
                        if draft.kind.hasOptions {
                            Picker("Choices from", selection: $draft.optionsFrom) {
                                Text("Typed below").tag("")
                                ForEach(categories.filter { !$0.items.isEmpty }) {
                                    Text($0.name).tag($0.id)
                                }
                            }
                            if draft.optionsFrom.isEmpty {
                                TextField("Choices, separated by commas", text: $draft.options)
                                    .font(.callout)
                            }
                        }
                        if draft.kind != .list {
                            Picker("Recorded", selection: $draft.after) {
                                Text("Before the run").tag(false)
                                Text("After the run").tag(true)
                            }
                        }
                        if draft.kind.isNumeric {
                            Picker("Best", selection: $draft.best) {
                                Text("Don't track").tag("")
                                Text(draft.kind == .time ? "Longest" : "Highest").tag("high")
                                Text(draft.kind == .time ? "Fastest" : "Lowest").tag("low")
                            }
                        }
                        Button("Remove Field", role: .destructive) {
                            drafts.removeAll { $0.id == draft.id }
                        }
                    } footer: {
                        Text(footer(for: draft))
                    }
                }

                Section {
                    Button {
                        suggest()
                    } label: {
                        if suggesting {
                            HStack { ProgressView(); Text("Asking what \(game.name) runs record…") }
                        } else {
                            Label("Suggest Fields for \(game.name)", systemImage: "sparkles")
                        }
                    }
                    .disabled(suggesting)
                    if let suggestion {
                        Text(suggestion)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Suggestions are added below for you to check. Nothing is saved until you tap Save.")
                }

                Section {
                    Menu {
                        ForEach(Draft.Kind.allCases) { kind in
                            Button(kind.label) { add(kind) }
                        }
                    } label: {
                        Label("Add a Field", systemImage: "plus")
                    }
                } footer: {
                    Text("A removed field's answers stay on the runs that recorded them.")
                }
            }
            .lsFormStyle()
            .navigationTitle("Run Fields")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(); dismiss() }
                }
            }
            .onAppear {
                guard !primed else { return }
                primed = true
                drafts = template.fields.map(Draft.init)
            }
        }
        .lsSheet()
    }

    private func footer(for draft: Draft) -> String {
        switch draft.kind {
        case .text: "Anything you type."
        case .select: "One pick from a list."
        case .multi: "Several picks from a list — the gods who showed up."
        case .number: "A score, a floor reached, a heat level."
        case .time: "Entered as 1:23.45. A run's clock time is kept separately."
        case .list: "Fills up while the run is live — boons, relics, jokers — and starts empty next run."
        }
    }

    /// Ask the generator what this game's runs record, and add what isn't
    /// here already. A field with the same id or name is left as you have it.
    private func suggest() {
        suggesting = true
        suggestion = nil
        let lists = categories.filter { !$0.items.isEmpty }.map { (id: $0.id, name: $0.name) }
        let name = game.name
        let igdbID = game.igdbID
        Task { @MainActor in
            defer { suggesting = false }
            do {
                let fields = try await AITrackerService.suggestRunFields(gameName: name, igdbID: igdbID, lists: lists)
                let haveIDs = Set(drafts.map(\.id))
                let haveNames = Set(drafts.map { $0.label.lowercased() })
                let fresh = fields.filter { !haveIDs.contains($0.id) && !haveNames.contains($0.label.lowercased()) }
                drafts += fresh.map(Draft.init)
                suggestion = fresh.isEmpty
                    ? "Nothing new — your fields already cover what was suggested."
                    : "Added \(fresh.map(\.label).joined(separator: ", ")). Check them, then Save."
            } catch {
                suggestion = error.localizedDescription
            }
        }
    }

    private func add(_ kind: Draft.Kind) {
        let label: String = switch kind {
        case .number: "Score"
        case .time: "Time"
        case .list: "Picked up"
        default: ""
        }
        drafts.append(Draft(id: "rf-\(UUID().uuidString.prefix(6).lowercased())",
                            label: label, kind: kind))
    }

    private func save() {
        var used = Set<String>()
        let fields: [RunFieldDTO] = drafts.compactMap { draft in
            var draft = draft
            draft.label = draft.label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !draft.label.isEmpty else { return nil }
            // A new field takes its name as its id, so a field removed and
            // added back by the same name finds its old answers.
            if draft.id.hasPrefix("rf-") {
                let slug = TrackerMerge.matchKey(draft.label).replacingOccurrences(of: " ", with: "-")
                if !slug.isEmpty { draft.id = slug }
            }
            guard used.insert(draft.id).inserted else { return nil }
            return draft.field
        }
        if fields != template.fields {
            repo.setRunFields(fields, for: game)
        }
    }
}
