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
    /// The sheet's tabs, when the link didn't name one and the sheet has more
    /// than one — the export only ever answers for a single tab.
    @State private var tabs: [SheetsLinkImport.Tab] = []
    @State private var tabGID: String?
    /// Choices for a roster's fields, read from the sheet's other tabs.
    @State private var rosterOptions: [String: [String]] = [:]
    /// The tab the rows came from, to name a list whose header doesn't.
    @State private var tabName: String?
    /// Bring the source's own ticks and counts in with the items.
    @State private var keepTicks = true
    /// The raw CSV the link gave, kept to send if it reads wrong.
    @State private var fetchedCSV: String?
    /// Why the last read or paste failed — offered to send to LevelSelect.
    @State private var failure: ImportFailureReport?

    private var repo: Repository { Repository(context) }

    /// Categories with any per-category corrections applied.
    private var categories: [TrackerListParser.ParsedCategory] {
        parsed.categories.map { category in
            var out = flipped.contains(category.id)
                ? TrackerListParser.flippingLeadingSegment(category) : category
            out.kind = category.kind
            // A roster needs somewhere to record its units' fields; before
            // the fields are deployed it comes in as an ordinary list.
            if out.kind == TrackerSchemaJSON.rosterKind {
                if SchemaDeploy.build39Fields {
                    out.fields = TrackerFieldDTO.rpgDefaults(options: rosterOptions)
                } else {
                    out.kind = nil
                }
            }
            return out
        }
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
                    .lsField()
                    .font(.caption)
                    #if !os(macOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                    .onSubmit { Task { await fetchLink(thenPreview: false) } }
                    // Another sheet's tabs aren't this one's.
                    .onChange(of: link) {
                        tabs = []; tabGID = nil; rosterOptions = [:]; tabName = nil
                        failure = nil; fetchedCSV = nil
                    }
                Button(fetchingLink ? "Reading…" : "Read") {
                    Task { await fetchLink(thenPreview: false) }
                }
                .disabled(fetchingLink || !SheetsLinkImport.looksLikeLink(link))
            }
            .padding(.horizontal)
            if tabs.count > 1 {
                Picker("Tab", selection: Binding(
                    get: { tabGID ?? tabs.first?.gid },
                    set: { gid in
                        tabGID = gid
                        Task { await fetchLink(thenPreview: false) }
                    })) {
                    ForEach(tabs) { tab in Text(tab.name).tag(String?.some(tab.gid)) }
                }
                .pickerStyle(.menu)
                .padding(.horizontal)
                .disabled(fetchingLink)
            }
            if let linkNote {
                Text(linkNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let failure {
                ImportReportButton(report: failure)
                    .padding(.horizontal)
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
        if parsed.isEmpty {
            // Nothing to show — say so, and offer to send it, rather than
            // leaving Preview looking like it did nothing.
            linkNote = "No list could be read from that."
            failure = currentReport(problem: "No list could be read from it.")
            return
        }
        failure = nil
        // "EmblemSkills" → "Emblem Skills", for a list whose header only said "Name".
        if let tabName {
            let readable = TrackerListParser.words(tabName).map(\.capitalized).joined(separator: " ")
            for i in parsed.categories.indices where parsed.categories[i].name == "Imported" && !readable.isEmpty {
                parsed.categories[i].name = readable
            }
        }
        flipped = []
        showingPreview = true
    }

    /// The link becomes the sheet's rows, in the editor — so what is about
    /// to be parsed is on screen, the same as a paste. Nothing is kept yet.
    private func fetchLink(thenPreview: Bool) async {
        fetchingLink = true
        linkNote = nil
        defer { fetchingLink = false }
        // Which tab: the one the link names, the one picked here, or — for a
        // link that names none — the choice of all of them.
        let named = SheetsLinkImport.tabID(from: link)
        if named == nil, tabs.isEmpty {
            tabs = await SheetsLinkImport.tabs(for: link)
        }
        let gid = named ?? tabGID
        failure = nil
        fetchedCSV = nil
        tabName = tabs.first { $0.gid == (gid ?? tabs.first?.gid) }?.name
        do {
            guard let export = SheetsLinkImport.exportURL(from: link, gid: gid) else {
                throw SheetsLinkImport.Failure.notASheetsLink
            }
            let csv = try await SheetsLinkImport.fetchCSV(export)
            fetchedCSV = csv
            let table = SheetsLinkImport.markdownTable(fromCSV: csv)
            guard !table.isEmpty else { throw SheetsLinkImport.Failure.notAList }
            text = table
            let rows = max(0, table.split(separator: "\n").count - 2)
            linkNote = "Read \(rows) row\(rows == 1 ? "" : "s")\(tabName.map { " from “\($0)”" } ?? " from the sheet"). Check the columns below, then Preview."
            // A roster's Class and Emblem choices come from the sheet's own
            // lists of them, when it has them.
            rosterOptions = [:]
            if TrackerListParser.parse(table).categories.contains(where: { $0.kind == TrackerSchemaJSON.rosterKind }),
               SchemaDeploy.build39Fields {
                rosterOptions = await SheetsLinkImport.referenceOptions(
                    link: link, tabs: tabs, excluding: gid ?? tabs.first?.gid)
            }
            if thenPreview { previewNow() }
        } catch {
            text = ""
            linkNote = error.localizedDescription
                + (tabs.count > 1 && error as? SheetsLinkImport.Failure == .notAList
                   ? " This sheet has \(tabs.count) tabs — choose one above." : "")
            // A sheet that can be downloaded but not read is worth sending;
            // one that can't be downloaded or reached isn't.
            let failed = error as? SheetsLinkImport.Failure
            if failed == .notAList || failed == .empty {
                failure = currentReport(problem: linkNote ?? "")
            }
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
                let ticked = categories.flatMap(\.items).filter { $0.done || ($0.count ?? 0) > 0 }.count
                if ticked > 0 {
                    Toggle(isOn: $keepTicks) {
                        Text("Keep the \(ticked) already ticked in the sheet")
                            .font(.subheadline)
                    }
                    .tint(LSTheme.accent)
                }
            }

            Section {
                ImportReportButton(report: currentReport(problem: "It read, but not the way the sheet is laid out."),
                                   label: "Didn't come out right? Send it to LevelSelect")
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
                            HStack(spacing: 6) {
                                if item.done {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(LSTheme.accent)
                                        .accessibilityLabel("Ticked")
                                }
                                Text(item.name).font(.subheadline)
                                if let target = item.countTarget {
                                    Text("\(item.count ?? 0)/\(target)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                if item.missable {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                        .accessibilityLabel("Missable")
                                }
                            }
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
                    if !category.fields.isEmpty {
                        Text("Each records " + category.fields.map { field in
                            field.options.isEmpty ? field.name : "\(field.name) (\(field.options.count) to choose from)"
                        }.joined(separator: " · ") + ". Change them after, from the list's menu.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    HStack {
                        Text("\(category.name) · \(category.items.count)")
                        if category.kind == TrackerSchemaJSON.rosterKind {
                            Label("Roster", systemImage: "person.3.fill")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(LSTheme.accent)
                        }
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

    /// What to send: the link and tab for a sheet, the text for a paste.
    private func currentReport(problem: String) -> ImportFailureReport {
        let fromLink = SheetsLinkImport.looksLikeLink(link) && fetchedCSV != nil
        return ImportFailureReport(
            source: fromLink ? "Google Sheets link" : "Pasted list",
            problem: problem,
            link: fromLink ? link.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            tab: fromLink ? tabName : nil,
            content: fromLink ? fetchedCSV : text)
    }

    // MARK: Apply

    private func apply() {
        var result = parsed
        result.categories = categories
        let incoming = TrackerListParser.schemaData(from: result)
        repo.ensureDefaultPlaythrough(for: game)
        // Append-only: an import should never be able to remove anything the
        // player already has.
        //
        // Provenance says a sheet by its link and a paste by the fact of it —
        // never the pasted text (Tim, 09-21).
        let fromLink = SheetsLinkImport.looksLikeLink(link) && fetchedCSV != nil
        repo.applyGeneratedSchema(
            for: game, jsonData: incoming, mode: .addAll,
            provenance: [fromLink ? .sheet(link) : .pasted])
        if keepTicks { applyTicks(result.categories) }
        dismiss()
    }

    /// The sheet's own ticks, onto the items that just arrived — found by
    /// list and name, since the merge may have re-keyed them.
    private func applyTicks(_ incoming: [TrackerListParser.ParsedCategory]) {
        let pt = repo.ensureDefaultPlaythrough(for: game)
        let installed = repo.trackerCategories(for: game)
        for category in incoming {
            guard let target = installed.first(where: { $0.id == category.id })
                ?? installed.first(where: { $0.name == category.name }) else { continue }
            var used = Set<String>()
            for item in category.items where item.done || (item.count ?? 0) > 0 {
                guard let match = target.items.first(where: { $0.id == item.id && !used.contains($0.id) })
                    ?? target.items.first(where: {
                        $0.name.caseInsensitiveCompare(item.name) == .orderedSame && !used.contains($0.id)
                    }) else { continue }
                used.insert(match.id)
                if let goal = match.countTarget, goal > 1 {
                    repo.setTrackerCount(pt, itemID: match.id, count: min(item.count ?? 0, goal), target: goal)
                } else if item.done {
                    repo.setTrackerItem(pt, itemID: match.id, done: true)
                }
            }
        }
    }
}
