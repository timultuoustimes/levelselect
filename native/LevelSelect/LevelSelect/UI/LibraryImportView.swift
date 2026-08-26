import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Settings → Your data → "Import LevelSelect export".
///
/// Pick the file → see exactly what would happen → decide. The preview and
/// the apply share one traversal, so the confirmation can never disagree
/// with the import.
struct LibraryImportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var pickingFile = true
    @State private var data: Data?
    @State private var preview: LibraryImport.Preview?
    @State private var outcome: LibraryImport.Outcome?
    @State private var error: String?
    @State private var applying = false

    var body: some View {
        NavigationStack {
            List {
                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(LSTheme.working)
                        Button("Pick a Different File") { pickingFile = true }
                    }
                } else if let outcome {
                    resultSections(outcome)
                } else if let preview {
                    previewSections(preview)
                } else {
                    Section {
                        Button {
                            pickingFile = true
                        } label: {
                            Label("Choose an export file", systemImage: "doc.badge.arrow.up")
                        }
                    } footer: {
                        Text("A .json file made by Settings → Your data → Export library — from this device, another device, or a backup.")
                    }
                }
            }
            .navigationTitle("Import Export")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(outcome == nil ? "Cancel" : "Done") { dismiss() }
                        .disabled(applying)
                }
            }
            .fileImporter(isPresented: $pickingFile, allowedContentTypes: [.json]) { result in
                load(result)
            }
            .interactiveDismissDisabled(applying)
        }
    }

    @ViewBuilder
    private func previewSections(_ preview: LibraryImport.Preview) -> some View {
        Section {
            ForEach(preview.creates.sorted(by: { $0.key < $1.key }), id: \.key) { kind, count in
                LabeledContent(kind.capitalized) {
                    Text("\(count)").monospacedDigit().foregroundStyle(LSTheme.accent)
                }
            }
            if preview.totalCreates == 0 {
                Text("Everything in this file is already in your library.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Will be restored")
        } footer: {
            Text(preview.totalSkips > 0
                 ? "\(preview.totalSkips) record\(preview.totalSkips == 1 ? " is" : "s are") already present and won't be touched — the import only ever adds what's missing."
                 : "The import only ever adds what's missing; nothing is overwritten or deleted.")
        }

        if !preview.problems.isEmpty {
            Section("Worth knowing") {
                ForEach(preview.problems, id: \.self) { problem in
                    Label(problem, systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }

        if preview.totalCreates > 0 {
            Section {
                if applying {
                    HStack { ProgressView(); Text("Restoring…") }
                } else {
                    Button {
                        apply()
                    } label: {
                        Label("Restore \(preview.totalCreates) record\(preview.totalCreates == 1 ? "" : "s")",
                              systemImage: "arrow.uturn.backward.circle")
                    }
                }
            } footer: {
                if !preview.exportedAt.isEmpty {
                    Text("Export made \(preview.exportedAt) by app version \(preview.appVersion).")
                }
            }
        }
    }

    @ViewBuilder
    private func resultSections(_ outcome: LibraryImport.Outcome) -> some View {
        Section("Restored") {
            if outcome.totalCreated == 0 {
                Label("Nothing needed restoring", systemImage: "checkmark.circle")
            }
            ForEach(outcome.created.sorted(by: { $0.key < $1.key }), id: \.key) { kind, count in
                LabeledContent(kind.capitalized) {
                    Text("\(count)").monospacedDigit().foregroundStyle(.green)
                }
            }
        }
    }

    private func load(_ result: Result<URL, Error>) {
        error = nil
        guard case .success(let url) = result else { return }
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }
        do {
            let bytes = try Data(contentsOf: url)
            data = bytes
            preview = try LibraryImport.preview(data: bytes, context: context)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func apply() {
        guard let data else { return }
        applying = true
        defer { applying = false }
        do {
            outcome = try LibraryImport.apply(data: data, context: context)
            WidgetBridge.refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
