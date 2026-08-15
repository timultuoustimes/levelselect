import SwiftUI
import SwiftData

/// Settings → Your Data: export everything, and scoped resets.
///
/// Export ships before the first external tester (beta P0): iCloud sync is not
/// a backup, and a tester who deletes the app should still have their hours.
struct DataSettingsSection: View {
    @Environment(\.modelContext) private var context

    @State private var exportURL: URL?
    @State private var exportSummary: String?
    @State private var exportError: String?
    @State private var exporting = false
    @State private var confirmingClear: ClearScope?
    @State private var clearResult: String?
    @State private var showingCSVImport = false

    enum ClearScope: String, Identifiable {
        case sessions, trackers
        var id: String { rawValue }

        var title: String {
            switch self {
            case .sessions: "Clear all play sessions?"
            case .trackers: "Clear all tracker progress?"
            }
        }
        var message: String {
            switch self {
            case .sessions:
                "Every logged session and its recorded time will be removed from all games. Your games, trackers, and collections are untouched. Export first if you might want this back — this can't be undone."
            case .trackers:
                "Every checked-off objective, rank, and run will be cleared from all games. The trackers themselves stay, so you can start over. Export first if you might want this back — this can't be undone."
            }
        }
        var confirm: String {
            switch self {
            case .sessions: "Clear Sessions"
            case .trackers: "Clear Progress"
            }
        }
    }

    var body: some View {
        Section {
            Button {
                runExport()
            } label: {
                if exporting {
                    HStack { ProgressView(); Text("Preparing export…") }
                } else {
                    Label("Export library", systemImage: "square.and.arrow.up")
                }
            }
            .disabled(exporting)

            if let exportSummary {
                Text(exportSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let exportError {
                Text(exportError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                showingCSVImport = true
            } label: {
                Label("Import from CSV", systemImage: "square.and.arrow.down")
            }
        } header: {
            Text("Your data")
        } footer: {
            Text("Export saves everything — games, sessions, tracker progress, playthroughs, runs, and collections — as a JSON file you can keep anywhere. iCloud keeps your devices in sync, but it isn't a backup. Import brings a library in from a CSV exported by another app or a spreadsheet.")
        }
        .sheet(item: $exportURL) { url in
            ShareSheet(url: url)
        }
        .sheet(isPresented: $showingCSVImport) {
            CSVImportView()
        }

        Section {
            Button(role: .destructive) {
                confirmingClear = .sessions
            } label: {
                Label("Clear all play sessions", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
            }
            Button(role: .destructive) {
                confirmingClear = .trackers
            } label: {
                Label("Clear all tracker progress", systemImage: "checklist.unchecked")
            }
            if let clearResult {
                Text(clearResult)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text("Start fresh without deleting your games.")
        }
        .alert(item: $confirmingClear) { scope in
            Alert(
                title: Text(scope.title),
                message: Text(scope.message),
                primaryButton: .destructive(Text(scope.confirm)) { runClear(scope) },
                secondaryButton: .cancel()
            )
        }
    }

    private func runExport() {
        exporting = true
        exportError = nil
        exportSummary = nil
        // Off the next runloop tick so the spinner actually appears on a big
        // library rather than the UI freezing mid-tap.
        Task { @MainActor in
            do {
                let data = try LibraryExport.makeJSON(context: context)
                exportSummary = LibraryExport.summary(for: data)
                let url = try LibraryExport.writeToTemporaryFile(context: context)
                exportURL = url
            } catch {
                exportError = "Couldn't build the export. \(error.localizedDescription)"
            }
            exporting = false
        }
    }

    private func runClear(_ scope: ClearScope) {
        let repo = Repository(context)
        switch scope {
        case .sessions:
            let n = repo.clearAllSessions()
            clearResult = "Cleared \(n) session\(n == 1 ? "" : "s")."
        case .trackers:
            let n = repo.clearAllTrackerProgress()
            clearResult = "Cleared progress on \(n) item\(n == 1 ? "" : "s")."
        }
    }
}

/// URL is Identifiable so it can drive a `.sheet(item:)`.
extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

#if os(iOS)
private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#else
private struct ShareSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 16) {
            Text("Export ready").font(.headline)
            Text(url.lastPathComponent).font(.caption).foregroundStyle(.secondary)
            ShareLink(item: url) { Label("Save…", systemImage: "square.and.arrow.up") }
            Button("Done") { dismiss() }
        }
        .padding(28)
    }
}
#endif
