import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Settings → Your Data: export everything, and scoped resets.
///
/// Export ships before the first external tester (beta P0): iCloud sync is not
/// a backup, and a tester who deletes the app should still have their hours.
struct DataSettingsSection: View {
    /// Which of the three sections to render.
    ///
    /// Getting data in and out is one destination; repairing and tidying what
    /// is already in the library is another. They were adjacent sections in
    /// one scroll, which made "Recently deleted" look like part of backup.
    /// Each scope keeps its own copy of this view's sheet and alert state, so
    /// the two pages present independently.
    enum Scope { case transfer, tools }
    var scope: Scope = .transfer

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
        case replace
        case erase

        var id: String {
            switch self {
            case .export(let url): "export:\(url.absoluteString)"
            case .csvImport:       "csv"
            case .libraryImport:   "libraryImport"
            case .metadataFill:    "fill"
            case .replace:         "replace"
            case .erase:           "erase"
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
        switch scope {
        case .transfer: transfer
        case .tools:    tools
        }
    }

    /// Getting the library in and out — the export that iCloud is not.
    @ViewBuilder
    private var transfer: some View {
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

            Button(role: .destructive) {
                sheet = .replace
            } label: {
                Label("Replace library with backup…", systemImage: "arrow.triangle.2.circlepath")
            }


            NavigationLink {
                ImageStorageView()
            } label: {
                Label("Game images", systemImage: "photo.stack")
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
                // `ShareSheet` is UIKit's own activity controller — it brings
                // its own presentation and detents do not belong on it.
                case .export(let url): ShareSheet(url: url)
                case .csvImport:       CSVImportView().lsSheet()
                case .libraryImport:    LibraryImportView().lsSheet()
                case .metadataFill:    MetadataFillView().lsSheet()
                case .replace:         LibraryStartOverView(mode: .replace).lsSheet()
                case .erase:           LibraryStartOverView(mode: .erase).lsSheet()
                }
            }
        } footer: {
            // The load-bearing sentence stays. The rest moved into the
            // workflows, which already explain themselves — a footer is read
            // after a row has been found, so it can't repair a wrong guess,
            // and this one ran longer than a phone screen.
            Text("iCloud keeps your devices in sync, but it isn't a backup — the export is. It writes your library to a readable JSON file, pictures you've added included. Import adds what's missing; Replace makes your library match the backup.")
        }
    }

    /// Repair and tidy what is already here, and the two scoped resets.
    @ViewBuilder
    private var tools: some View {
        Section {
            Button {
                sheet = .metadataFill
            } label: {
                Label("Update missing game details", systemImage: "sparkle.magnifyingglass")
            }
            // Its own presentation, because this scope is now a separate
            // screen from the one that owns the export/import sheet — and,
            // as above, on the ROW rather than the Section.
            .sheet(item: $sheet) { which in
                switch which {
                case .export(let url): ShareSheet(url: url)
                case .csvImport:       CSVImportView().lsSheet()
                case .libraryImport:   LibraryImportView().lsSheet()
                case .metadataFill:    MetadataFillView().lsSheet()
                case .replace:         LibraryStartOverView(mode: .replace).lsSheet()
                case .erase:           LibraryStartOverView(mode: .erase).lsSheet()
                }
            }

            NavigationLink {
                ManageTagsView()
            } label: {
                Label("Manage tags", systemImage: "tag")
            }

            NavigationLink {
                RecentlyDeletedView()
            } label: {
                Label("Recently deleted", systemImage: "trash")
            }
        } footer: {
            // Maintenance is not backup. These three answer "repair or tidy
            // what's in my library", which is a different question from "get
            // my data in or out" — filing them under a data/export heading
            // made a wrong first guess rational.
            Text("Update missing game details fills only what's blank, so nothing you've corrected by hand is touched.")
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
            Button(role: .destructive) {
                sheet = .erase
            } label: {
                Label("Erase library…", systemImage: "trash.slash")
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
            Text("Clear sessions or progress without deleting your games, or erase the whole library to start over. Erasing saves a copy first and moves everything to Recently Deleted.")
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
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#else
/// **A save panel, not a share menu.**
///
/// `ShareLink` on the Mac opens the system share menu — AirDrop, Mail,
/// Messages, Notes, Copy — and macOS's share menu has no save-to-disk action
/// at all. So a button labelled "Save…" could do everything except save. Tim,
/// 2026-09-10: *"exporting on mac opens a share sheet when I hit save, and
/// doesn't let me save to files."*
///
/// iOS keeps the share sheet, where "Save to Files" is one of the choices and
/// AirDropping the export to another device is a real thing people do.
struct ShareSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var saving = false
    @State private var saveError: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("Export ready").font(.headline)
            Text(url.lastPathComponent).font(.caption).foregroundStyle(.secondary)
            Button { saving = true } label: {
                Label("Save…", systemImage: "square.and.arrow.down")
            }
            if let saveError {
                Text(saveError).font(.caption).foregroundStyle(LSTheme.working)
            }
            Button("Done") { dismiss() }
        }
        .padding(28)
        // The document references the file on disk rather than reading it
        // into memory — an export carries every picture you have added, so it
        // is not always small.
        .fileExporter(isPresented: $saving,
                      document: ExportedFile(url: url),
                      contentType: .json,
                      defaultFilename: url.deletingPathExtension().lastPathComponent) { result in
            switch result {
            case .success: dismiss()
            case .failure(let error): saveError = error.localizedDescription
            }
        }
    }
}

/// The export as something `fileExporter` can write, without copying its
/// bytes through memory first.
private struct ExportedFile: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    let url: URL

    init(url: URL) { self.url = url }

    /// Never read back — this document only ever travels outward.
    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.fileReadUnsupportedScheme)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try FileWrapper(url: url)
    }
}
#endif
