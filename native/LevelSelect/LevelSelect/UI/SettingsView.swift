import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<Game> { $0.deletedAt == nil }) private var games: [Game]

    // Tim's one-time migration from the web app. Debug builds only — the
    // bundled export is personal data and the actions are a developer tool,
    // so neither ships in a Release build. See project.yml.
    #if LEGACY_IMPORT
    @Query private var receipts: [MigrationReceipt]

    @State private var importing = false
    @State private var result: ImportReport?
    @State private var errorMessage: String?
    @State private var progressSynced: Int?

    // The canonical legacy device this bundled export came from.
    private let sourceDeviceID = "7f86df1b-a815-4798-a9d5-00974419eec3"

    /// Result text from the CloudKit schema seeder/purge and demo library.
    @State private var seedResult: String?
    @State private var seedingDemo = false
    #endif

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // Live type rather than the baked lockup PNG: stays crisp
                    // at any size and follows the user's accent color.
                    Wordmark(size: 22, showsIcon: true)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                Section("Library") {
                    LabeledContent("Games", value: "\(games.count)")
                }

                SyncStatusSection()

                AppearanceSettingsSection()

                #if LEGACY_IMPORT
                Section {
                    if let r = result {
                        importSummary(r)
                    }
                    if importing {
                        HStack { ProgressView(); Text("Importing…") }
                    }
                    Button {
                        runImport()
                    } label: {
                        Label(receipts.isEmpty ? "Import from LevelSelect web" : "Re-run import",
                              systemImage: "square.and.arrow.down")
                    }
                    .disabled(importing)

                    if !receipts.isEmpty && result == nil {
                        Text("Already imported — re-running is a no-op (idempotent).")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let e = errorMessage {
                        Text(e).font(.caption).foregroundStyle(.red)
                    }
                } header: {
                    Text("Import legacy library")
                } footer: {
                    Text("Brings your existing library in from the web app's data. Safe to tap more than once. Syncs to your other devices via iCloud.")
                }

                Section {
                    if let n = progressSynced {
                        Label("Synced \(n) tracker items", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    Button {
                        syncProgress()
                    } label: {
                        Label("Sync tracker progress", systemImage: "checklist")
                    }
                } footer: {
                    Text("Backfills checked-off tracker items from the web app's data into an already-imported library. Safe to repeat.")
                }

                Section {
                    Button {
                        seedResult = CloudKitSchemaSeeder.seed(context: context)
                    } label: {
                        Label("Seed CloudKit schema", systemImage: "cloud.bolt")
                    }
                    Button(role: .destructive) {
                        seedResult = CloudKitSchemaSeeder.purge(context: context)
                    } label: {
                        Label("Purge seed records", systemImage: "trash")
                    }
                    if let seedResult {
                        Text(seedResult)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Developer — CloudKit schema")
                } footer: {
                    Text("Writes one hidden, fully-populated record of every model so the Development schema gains every field. Seed → wait for Synced → Deploy Schema Changes to Production in CloudKit Console → Purge.")
                }

                Section {
                    Button {
                        seedingDemo = true
                        Task {
                            seedResult = await DemoLibrarySeeder.seed(context: context)
                            seedingDemo = false
                        }
                    } label: {
                        if seedingDemo {
                            HStack { ProgressView(); Text("Building demo library…") }
                        } else {
                            Label("Load demo library", systemImage: "sparkles")
                        }
                    }
                    .disabled(seedingDemo)
                    Button(role: .destructive) {
                        seedResult = DemoLibrarySeeder.purge(context: context)
                    } label: {
                        Label("Remove demo library", systemImage: "trash")
                    }
                } header: {
                    Text("Developer — screenshots")
                } footer: {
                    Text("12 well-known games with real IGDB art, play history, a populated tracker, a run record, and a collection — so marketing shots contain no personal data. Deterministic, so retakes look identical.")
                }
                #endif

                AboutSection()
            }
            .navigationTitle("Settings")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    #if LEGACY_IMPORT
    private func importSummary(_ r: ImportReport) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if r.alreadyImported {
                Label("Already imported — nothing to do.", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            } else {
                Label("Imported \(r.games) games", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("\(r.playthroughs) playthroughs · \(r.sessions) sessions · \(r.completionEvents) completions · \(r.trackerSchemas) trackers · \(r.maps) maps")
                    .font(.caption).foregroundStyle(.secondary)
                if !r.skipped.isEmpty {
                    Text("Skipped \(r.skipped.count)").font(.caption).foregroundStyle(.orange)
                }
            }
        }
        .font(.subheadline)
    }

    private func syncProgress() {
        errorMessage = nil
        guard let url = Bundle.main.url(forResource: "legacy-import", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            errorMessage = "Bundled export not found."
            return
        }
        do {
            progressSynced = try LegacyImporter(context).syncTrackerProgress(data: data)
            try context.save()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func runImport() {
        importing = true
        errorMessage = nil
        result = nil
        defer { importing = false }
        guard let url = Bundle.main.url(forResource: "legacy-import", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            errorMessage = "Bundled export not found."
            return
        }
        do {
            let report = try LegacyImporter(context).import(
                data: data,
                sourceDeviceID: sourceDeviceID,
                appVersion: "0.1.0"
            )
            try context.save()
            result = report
        } catch {
            errorMessage = String(describing: error)
        }
    }
    #endif
}
