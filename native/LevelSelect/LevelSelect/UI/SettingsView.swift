import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<Game> { $0.deletedAt == nil }) private var games: [Game]
    @Query private var receipts: [MigrationReceipt]

    @State private var importing = false
    @State private var result: ImportReport?
    @State private var errorMessage: String?
    @State private var progressSynced: Int?

    // The canonical legacy device this bundled export came from.
    private let sourceDeviceID = "7f86df1b-a815-4798-a9d5-00974419eec3"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Image("LockupWide")
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .frame(maxWidth: 420)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("LevelSelect")
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                Section("Library") {
                    LabeledContent("Games", value: "\(games.count)")
                }

                AppearanceSettingsSection()

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
}
