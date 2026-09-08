import SwiftUI
import SwiftData

/// Paste a community checklist and turn it straight into tracker items.
///
/// No generation, no quota, no waiting, and nothing invented — a checklist
/// someone has already written is better data than anything a model can guess,
/// so the job here is to read it faithfully rather than to interpret it.
/// Imported categories arrive locked, so a later regeneration can't quietly
/// replace them.
struct TrackerListImportView: View {
    @Bindable var game: Game
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var parsed = TrackerListParser.Result()
    @State private var flipped: Set<String> = []
    @State private var showingPreview = false
    /// A Google Sheets link, read into the editor as a table. See
    /// `SheetsLinkImport` for why this tier and not the API.
    @State private var link = ""
    @State private var fetchingLink = false
    @State private var linkNote: String?

    private var repo: Repository { Repository(context) }

    /// Categories with any per-category corrections applied.
    private var categories: [TrackerListParser.ParsedCategory] {
        parsed.categories.map { flipped.contains($0.id)
            ? TrackerListParser.flippingLeadingSegment($0) : $0 }
    }

    var body: some View {
        NavigationStack {
            Group {
                if showingPreview && !parsed.isEmpty {
                    preview
                } else {
                    entry
                }
            }
            .navigationTitle(showingPreview ? "Review Import" : "Paste a List")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(showingPreview ? "Back" : "Cancel") {
                        if showingPreview { showingPreview = false } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if showingPreview {
                        Button("Import") { apply() }
                    } else {
                        Button("Preview") {
                            // A bare Sheets link in the editor is the same
                            // ask as the field above it.
                            if SheetsLinkImport.looksLikeLink(text) {
                                link = text
                                Task { await fetchLink(thenPreview: true) }
                            } else {
                                previewNow()
                            }
                        }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || fetchingLink)
                    }
                }
            }
        }
    }

    // MARK: Entry

    private var entry: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Paste a checklist — a markdown table, or sections with numbered items. Nothing is sent anywhere and nothing is invented: every item comes from your text, with list syntax stripped and names and locations read out of it. The preview shows exactly how it was read.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            // Or a Google Sheets link. The tab's rows come back as the
            // table below, where they can be read before anything is kept.
            HStack(spacing: 8) {
                TextField("Or paste a Google Sheets link", text: $link)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    #if !os(macOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                    .onSubmit { Task { await fetchLink(thenPreview: false) } }
                Button(fetchingLink ? "Reading…" : "Read") {
                    Task { await fetchLink(thenPreview: false) }
                }
                .disabled(fetchingLink || !SheetsLinkImport.looksLikeLink(link))
            }
            .padding(.horizontal)
            if let linkNote {
                Text(linkNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TextEditor(text: $text)
                .font(.system(.caption, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(.black.opacity(0.25), in: .rect(cornerRadius: 10))
                .padding(.horizontal)
                .frame(maxHeight: .infinity)
        }
        .padding(.vertical)
        .lsBackground()
    }

    private func previewNow() {
        parsed = TrackerListParser.parse(text, defaultCategoryName: "Imported")
        flipped = []
        showingPreview = true
    }

    /// The link becomes the sheet's rows, in the editor — so what is about
    /// to be parsed is on screen, the same as a paste. Nothing is kept yet.
    private func fetchLink(thenPreview: Bool) async {
        fetchingLink = true
        linkNote = nil
        defer { fetchingLink = false }
        do {
            let table = try await SheetsLinkImport.table(from: link)
            text = table
            let rows = max(0, table.split(separator: "\n").count - 2)
            linkNote = "Read \(rows) row\(rows == 1 ? "" : "s") from the sheet. Check the columns below, then Preview."
            if thenPreview { previewNow() }
        } catch {
            linkNote = error.localizedDescription
        }
    }

    // MARK: Preview

    private var preview: some View {
        List {
            Section {
                Label("\(parsed.itemCount) items in \(categories.count) categor\(categories.count == 1 ? "y" : "ies")",
                      systemImage: "checklist")
                    .font(.subheadline.weight(.semibold))
                Label("Imported categories are locked, so regenerating this tracker won't replace them.",
                      systemImage: "lock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(parsed.warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            ForEach(categories) { category in
                Section {
                    ForEach(category.items.prefix(8)) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(.subheadline)
                            if let location = item.location {
                                Label(location, systemImage: "mappin.and.ellipse")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if let detail = item.detail {
                                Text(detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if category.items.count > 8 {
                        Text("+ \(category.items.count - 8) more")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                } header: {
                    HStack {
                        Text("\(category.name) · \(category.items.count)")
                        Spacer()
                        // The parser guesses whether a leading "Foo - " is a
                        // place or the item's name by seeing whether it
                        // repeats. It's right on both real lists this was
                        // built against, and wrong on genuinely mixed
                        // sections — so the correction is one tap.
                        Button(category.leadingSegmentIsLocation
                               ? "Reading as: Location" : "Reading as: Name") {
                            if flipped.contains(category.id) { flipped.remove(category.id) }
                            else { flipped.insert(category.id) }
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    // MARK: Apply

    private func apply() {
        var result = parsed
        result.categories = categories
        let incoming = TrackerListParser.schemaData(from: result)
        repo.ensureDefaultPlaythrough(for: game)
        // Append-only: an import should never be able to remove anything the
        // player already has.
        repo.applyGeneratedSchema(for: game, jsonData: incoming, mode: .addAll)
        dismiss()
    }
}
