import SwiftUI
import SwiftData

/// Settings → Your Data: export everything, and scoped resets.
///
/// Export ships before the first external tester (beta P0): iCloud sync is not
/// a backup, and a tester who deletes the app should still have their hours.
struct DataSettingsSection: View {
    @Environment(\.modelContext) private var context

    @State private var sheet: DataSheet?
    @State private var exportSummary: String?
    @State private var exportError: String?
    @State private var exporting = false
    @State private var confirmingClear: ClearScope?
    @State private var clearResult: String?

    /// Which sheet this section is showing.
    ///
    /// ONE `.sheet` modifier drives all three. SwiftUI registers a single
    /// sheet presentation per view, so stacking modifiers means only one of
    /// them reliably wins — the losers present and are dismissed again in the
    /// same breath, which looks exactly like a sheet that flickers open and
    /// shuts and swallows whatever you tapped inside it. Two were already
    /// stacked here; adding a third is what made it show.
    private enum DataSheet: Identifiable {
        case export(URL)
        case csvImport
        case libraryImport
        case metadataFill

        var id: String {
            switch self {
            case .export(let url): "export:\(url.absoluteString)"
            case .csvImport:       "csv"
            case .libraryImport:   "libraryImport"
            case .metadataFill:    "fill"
            }
        }
    }

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
                sheet = .csvImport
            } label: {
                Label("Import from CSV", systemImage: "square.and.arrow.down")
            }

            Button {
                sheet = .libraryImport
            } label: {
                Label("Import LevelSelect export", systemImage: "arrow.uturn.backward.circle")
            }

            Button {
                sheet = .metadataFill
            } label: {
                Label("Fill in missing game info", systemImage: "sparkle.magnifyingglass")
            }

            NavigationLink {
                ManageTagsView()
            } label: {
                Label("Manage Tags", systemImage: "tag")
            }

            NavigationLink {
                RecentlyDeletedView()
            } label: {
                Label("Recently Deleted", systemImage: "trash")
            }
            // The sheet hangs off THIS ROW, not off the Section.
            //
            // `Section` is not a view that can host a presentation, so a
            // `.sheet` written against it is pushed down into every child it
            // has — here five of them (three buttons and two conditional
            // captions). That is five presentations bound to one piece of
            // state: they all fire together, collide, and dismiss each other
            // about a second later, taking any tap inside with them. It looks
            // precisely like a sheet that flickers open and shuts.
            //
            // A row is a single view, so the modifier stays singular. Keep it
            // on an UNCONDITIONAL row — attach it to one of the captions above
            // and the sheet would vanish whenever that caption did.
            .sheet(item: $sheet) { which in
                switch which {
                case .export(let url): ShareSheet(url: url)
                case .csvImport:       CSVImportView()
                case .libraryImport:    LibraryImportView()
                case .metadataFill:    MetadataFillView()
                }
            }
        } header: {
            Text("Your data")
        } footer: {
            Text("Export writes your library's content — games, playthroughs, sessions, runs, tracker progress and notes, maps and markers, videos, collections, and appearance settings — to a readable JSON file you can keep anywhere. Import LevelSelect export reads that same file back, restoring anything that's missing and never touching what's already here — so an old export plus a current library merge safely. One honest limit: map images are saved as links rather than embedded. iCloud keeps your devices in sync, but it isn't a backup; the export is. Import from CSV brings a library in from another app or a spreadsheet. Fill in missing game info looks up everything your games are missing — release dates, genres, developers, cover art — and adds only what's blank, so nothing you've corrected by hand is touched.")
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
            // On a row, not the Section — same reason as the sheet above. This
            // one had not visibly misbehaved, but it is the identical shape:
            // three children, so three alerts bound to one piece of state.
            .alert(item: $confirmingClear) { scope in
                Alert(
                    title: Text(scope.title),
                    message: Text(scope.message),
                    primaryButton: .destructive(Text(scope.confirm)) { runClear(scope) },
                    secondaryButton: .cancel()
                )
            }
            if let clearResult {
                Text(clearResult)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text("Start fresh without deleting your games.")
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
                let url = try LibraryExport.writeToTemporaryFile(data: data)
                sheet = .export(url)
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
