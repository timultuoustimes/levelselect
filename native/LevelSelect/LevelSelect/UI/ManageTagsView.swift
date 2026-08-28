import SwiftUI
import SwiftData

/// The library's tag vocabulary — rename, merge, remove.
///
/// Autocomplete (in the game-page tag field) prevents NEW fragmentation;
/// this screen is the recovery tool for a library that already split into
/// `roguelike` / `rogue-like` / `Roguelike`, which is every library by the
/// time anyone notices. Renaming onto an existing tag IS the merge — you
/// pick which name survives — and every destructive step says how many games
/// it touches before it happens.
struct ManageTagsView: View {
    @Environment(\.modelContext) private var context

    @State private var counts: [(tag: String, count: Int)] = []
    @State private var renaming: String?
    @State private var renameText = ""
    @State private var confirmingMerge: (from: String, to: String)?
    @State private var removing: String?

    private var repo: Repository { Repository(context) }

    @ViewBuilder
    private func tagActions(_ tag: String) -> some View {
        Button {
            renameText = tag
            renaming = tag
        } label: { Label("Rename or Merge…", systemImage: "pencil") }
        Button(role: .destructive) {
            removing = tag
        } label: { Label("Remove from all games", systemImage: "trash") }
    }

    var body: some View {
        List {
            if counts.isEmpty {
                ContentUnavailableView("No tags yet", systemImage: "tag",
                                       description: Text("Tags you add to games collect here."))
            } else {
                Section {
                    ForEach(counts, id: \.tag) { row in
                        HStack {
                            Text("#\(row.tag)")
                            Spacer()
                            Text("\(row.count)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            // Every route into tag management used to be a long
                            // press, which is why the footer had to teach the
                            // gesture. A hidden gesture can be a shortcut; it
                            // can't be the only door.
                            Menu {
                                tagActions(row.tag)
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityLabel("Actions for #\(row.tag)")
                        }
                        .contentShape(.rect)
                        .contextMenu { tagActions(row.tag) }
                    }
                } footer: {
                    Text("Rename a tag to an existing name to merge them — games holding both end up with one.")
                }
            }
        }
        .navigationTitle("Tags")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear { counts = repo.tagCounts() }
        .alert("Rename #\(renaming ?? "")", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )) {
            TextField("New name", text: $renameText)
            Button("Rename") {
                guard let old = renaming else { return }
                let new = renameText
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "#", with: "")
                guard !new.isEmpty, new != old else { return }
                if counts.contains(where: { $0.tag == new }) {
                    // Existing target → this is a merge; say the numbers first.
                    confirmingMerge = (from: old, to: new)
                } else {
                    repo.renameTag(old, to: new)
                    counts = repo.tagCounts()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Renaming to an existing tag merges the two.")
        }
        .confirmationDialog(
            mergeTitle,
            isPresented: Binding(
                get: { confirmingMerge != nil },
                set: { if !$0 { confirmingMerge = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Merge") {
                if let merge = confirmingMerge {
                    repo.renameTag(merge.from, to: merge.to)
                    counts = repo.tagCounts()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            removeTitle,
            isPresented: Binding(
                get: { removing != nil },
                set: { if !$0 { removing = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove Tag", role: .destructive) {
                if let tag = removing {
                    repo.removeTag(tag)
                    counts = repo.tagCounts()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var mergeTitle: String {
        guard let merge = confirmingMerge else { return "" }
        let from = counts.first { $0.tag == merge.from }?.count ?? 0
        return "Merge #\(merge.from) into #\(merge.to)? \(from) game\(from == 1 ? "" : "s") will change; #\(merge.from) disappears."
    }

    private var removeTitle: String {
        guard let tag = removing else { return "" }
        let count = counts.first { $0.tag == tag }?.count ?? 0
        return "Remove #\(tag) from \(count) game\(count == 1 ? "" : "s")? The games stay; only the tag goes."
    }
}
