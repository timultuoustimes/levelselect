import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Settings → Replace Library with Backup, and Erase Library.
///
/// Both are one sheet with the same safeguards: say exactly what will happen,
/// save a copy of the library first, and make the person type the word
/// before the button works. Nothing is deleted outright — whatever leaves the
/// library goes to Recently Deleted. See `LibraryReplace`.
struct LibraryStartOverView: View {
    enum Mode { case replace, erase }
    let mode: Mode

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var pickingFile = false
    @State private var data: Data?
    @State private var preview: LibraryReplace.Preview?
    @State private var eraseCounts: [String: Int]?
    @State private var outcome: LibraryReplace.Outcome?
    @State private var error: String?
    @State private var typed = ""
    @State private var working = false

    private var word: String { mode == .replace ? "REPLACE" : "ERASE" }
    private var title: String { mode == .replace ? "Replace Library" : "Erase Library" }
    private var armed: Bool {
        typed.trimmingCharacters(in: .whitespaces).uppercased() == word && !working
    }

    var body: some View {
        NavigationStack {
            List {
                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(LSTheme.working)
                        if mode == .replace {
                            Button("Pick a Different File") { pickingFile = true }
                        }
                    }
                } else if let outcome {
                    resultSections(outcome)
                } else if mode == .erase, let eraseCounts {
                    eraseSections(eraseCounts)
                } else if let preview {
                    replaceSections(preview)
                } else if mode == .replace {
                    Section {
                        Button {
                            pickingFile = true
                        } label: {
                            Label("Choose a backup file", systemImage: "doc.badge.arrow.up")
                        }
                    } footer: {
                        Text("A .json file made by Export library. Your library will be made to match it: what the backup has comes back as it was, and what it doesn't have moves to Recently Deleted.")
                    }
                }
            }
            .navigationTitle(title)
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(outcome == nil ? "Cancel" : "Done") { dismiss() }
                        .disabled(working)
                }
            }
            .fileImporter(isPresented: $pickingFile, allowedContentTypes: [.json]) { result in
                load(result)
            }
            .interactiveDismissDisabled(working)
            .task {
                if mode == .erase {
                    do { eraseCounts = try LibraryReplace.erasePreview(context: context) }
                    catch { self.error = error.localizedDescription }
                } else {
                    #if !os(macOS)
                    // Opens by itself on iPhone and iPad; on the Mac a panel
                    // raised as the sheet appears is left blank behind it
                    // (see `LibraryImportView`).
                    if data == nil { pickingFile = true }
                    #endif
                }
            }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private func replaceSections(_ preview: LibraryReplace.Preview) -> some View {
        Section {
            row("Games in the backup", preview.gamesInBackup)
            row("Records that will match the backup", preview.matched)
            if preview.revived > 0 { row("Coming back from Recently Deleted", preview.revived) }
            if preview.added > 0 { row("Added from the backup", preview.added) }
        } header: {
            Text("From the backup")
        } footer: {
            if !preview.exportedAt.isEmpty {
                Text("Backup made \(preview.exportedAt) by version \(preview.appVersion). Records that match take the backup's values, so anything you've changed since it was made goes back.")
            }
        }
        removalSection(preview.removed,
                       empty: "Nothing in your library is missing from the backup.")
        confirmSection
    }

    @ViewBuilder
    private func eraseSections(_ counts: [String: Int]) -> some View {
        removalSection(counts, empty: "Your library is already empty.")
        if !counts.isEmpty {
            Section {
                Label("Your appearance settings and profile stay.", systemImage: "paintpalette")
                Label("To bring a backup back afterwards, use Replace Library with Backup. Import only adds what's missing, and erased records still count as there.",
                      systemImage: "arrow.uturn.backward.circle")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            confirmSection
        }
    }

    @ViewBuilder
    private func removalSection(_ counts: [String: Int], empty: String) -> some View {
        Section {
            if counts.isEmpty {
                Text(empty).foregroundStyle(.secondary)
            }
            ForEach(counts.sorted(by: { $0.key < $1.key }), id: \.key) { kind, count in
                LabeledContent(kind.capitalized) {
                    Text("\(count)").monospacedDigit().foregroundStyle(LSTheme.working)
                }
            }
        } header: {
            Text("Moves to Recently Deleted")
        } footer: {
            Text("Recently Deleted keeps them for 30 days, and anything there can be restored. Running timers are stopped first.")
        }
    }

    private var confirmSection: some View {
        Section {
            TextField("Type \(word) to confirm", text: $typed)
                .autocorrectionDisabled()
                #if !os(macOS)
                .textInputAutocapitalization(.characters)
                #endif
            Button(role: .destructive) {
                run()
            } label: {
                if working {
                    HStack { ProgressView(); Text(mode == .replace ? "Replacing…" : "Erasing…") }
                } else {
                    Label(title, systemImage: mode == .replace ? "arrow.triangle.2.circlepath" : "trash")
                }
            }
            .disabled(!armed)
        } footer: {
            Text("First, a copy of your library as it is now is saved to \(LibraryReplace.safetyFolderDescription). Every device signed in to your iCloud account gets the change.")
        }
    }

    @ViewBuilder
    private func resultSections(_ outcome: LibraryReplace.Outcome) -> some View {
        Section(mode == .replace ? "Replaced" : "Erased") {
            if mode == .replace {
                row("Matched to the backup", outcome.matched)
                if outcome.revived > 0 { row("Brought back", outcome.revived) }
                if outcome.added > 0 { row("Added", outcome.added) }
            }
            row("Moved to Recently Deleted", outcome.totalRemoved)
        }
        if let copy = outcome.safetyCopy {
            Section {
                #if os(macOS)
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([copy])
                } label: {
                    Label("Show the safety copy in Finder", systemImage: "folder")
                }
                #else
                ShareLink(item: copy) {
                    Label("Share the safety copy", systemImage: "square.and.arrow.up")
                }
                #endif
            } footer: {
                Text("Saved as “\(copy.lastPathComponent)” in \(LibraryReplace.safetyFolderDescription). Replace Library with that file puts things back the way they were.")
            }
        }
    }

    private func row(_ label: String, _ count: Int) -> some View {
        LabeledContent(label) { Text("\(count)").monospacedDigit() }
    }

    // MARK: Actions

    private func load(_ result: Result<URL, Error>) {
        error = nil
        guard case .success(let url) = result else { return }
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }
        do {
            let bytes = try Data(contentsOf: url)
            preview = try LibraryReplace.preview(data: bytes, context: context)
            data = bytes
            typed = ""
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func run() {
        guard armed else { return }
        working = true
        Task { @MainActor in
            defer { working = false }
            do {
                switch mode {
                case .replace:
                    guard let data else { return }
                    outcome = try LibraryReplace.apply(data: data, context: context)
                case .erase:
                    outcome = try LibraryReplace.erase(context: context)
                }
                WidgetBridge.refresh()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
