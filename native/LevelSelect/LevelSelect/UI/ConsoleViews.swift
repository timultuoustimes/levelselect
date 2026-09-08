import SwiftUI
import SwiftData

/// The console itself, at the top of its own page.
///
/// **The hardware above the games, because that is the claim this feature
/// makes.** The page was a filtered list of games that happened to be titled
/// "Genesis"; the console record is a thing you own, with its own ownership,
/// its own variant and its own history, and the games are what you have on
/// it. Tim's four photographs, 2026-08-31: in every one the games are on
/// shelves and the console is the display.
struct ConsoleCard: View {
    /// The canonical platform this page is.
    let platform: String
    /// Every live game, for counting the questions.
    let games: [Game]

    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Console> { $0.deletedAt == nil }) private var consoles: [Console]
    @State private var editing = false

    private var repo: Repository { Repository(context) }
    private var key: String { PlatformKey.canonical(platform) }
    private var console: Console? { consoles.first { $0.platform == key } }

    /// Only this console's questions — the page is about one machine.
    private var questions: [ConsoleQuestion] {
        repo.pendingConsoleQuestions(in: games).filter { $0.platform == key }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let console {
                Button { editing = true } label: { summary(console) }
                    .buttonStyle(.plain)
                ForEach(questions) { question in
                    ask(question)
                }
            } else {
                addRow
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .sheet(isPresented: $editing) {
            if let console { ConsoleEditor(console: console).lsSheet() }
        }
    }

    private func summary(_ console: Console) -> some View {
        HStack(spacing: 12) {
            PlatformIconView(platform: platform, size: 40)
                .frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 3) {
                Text(PlatformShort.name(platform))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                if console.ownership.isEmpty && detail(console) == nil {
                    Text("Tap to say how you have it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    if !console.ownership.isEmpty {
                        Text(console.ownership.compactMap { Ownership(rawValue: $0)?.label }
                            .joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(LSTheme.accent)
                    }
                    if let detail = detail(console) {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(LSTheme.cardFill, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(LSTheme.hairline))
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Edit this console")
    }

    /// Variant, when you got it, and your note — whichever of them exist.
    private func detail(_ console: Console) -> String? {
        var parts: [String] = []
        if let v = console.variant, !v.isEmpty { parts.append(v) }
        if let date = console.acquiredAt {
            parts.append("since \(date.formatted(.dateTime.year()))")
        }
        if let n = console.notes, !n.isEmpty { parts.append(n) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The question, where the console is — not as an alert while you were
    /// doing something else. It carries its count, because that is the fact
    /// that makes it answerable.
    private func ask(_ question: ConsoleQuestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(questionText(question))
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Yes") { repo.answer(question, yes: true) }
                    .buttonStyle(LSPrimaryButtonStyle(cornerRadius: 10))
                Button("No") { repo.answer(question, yes: false) }
                    .font(.callout.weight(.semibold))
                    .buttonStyle(.bordered)
                    .tint(.secondary)
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .background(LSTheme.accent.opacity(0.10), in: .rect(cornerRadius: 14))
    }

    /// One game is a display copy; eleven is a machine — so the count leads,
    /// and it has to agree with its verb.
    private func questionText(_ q: ConsoleQuestion) -> String {
        let name = PlatformShort.name(platform)
        let kind = q.ownership.label.lowercased()
        return q.games == 1
            ? "One of your \(name) games is \(kind). Do you have the console that way too?"
            : "\(q.games) of your \(name) games are \(kind). Do you have the console that way too?"
    }

    private var addRow: some View {
        Button {
            repo.addConsole(platform: key)
            editing = true
        } label: {
            HStack(spacing: 12) {
                PlatformIconView(platform: platform, size: 34)
                    .frame(width: 44, height: 44)
                    .opacity(0.5)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add this console")
                        .font(.subheadline.weight(.medium))
                    Text("How you have it, which model, when you got it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "plus.circle")
                    .foregroundStyle(LSTheme.accent)
            }
            .padding(12)
            .background(LSTheme.cardFill.opacity(0.6), in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(LSTheme.accent.opacity(0.4),
                              style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
        }
        .buttonStyle(.plain)
    }
}

/// Everything a console record holds, on one sheet.
struct ConsoleEditor: View {
    @Bindable var console: Console
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var variant = ""
    @State private var notes = ""
    @State private var knowsAcquired = false
    @State private var acquired = Date.now
    @State private var confirmingDelete = false
    @State private var loaded = false

    private var repo: Repository { Repository(context) }

    var body: some View {
        NavigationStack {
            Form {
                // The app's own card fill, so the rows keep the theme at any
                // detent — see `SettingsPage` for why the system's grey drains.
                Group {
                    Section {
                        HStack(spacing: 12) {
                            PlatformIconView(platform: console.platform, size: 44)
                                .frame(width: 58, height: 58)
                            Text(PlatformShort.name(console.platform))
                                .font(.title3.weight(.semibold))
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 2)
                    }

                    Section {
                        OwnershipControl(ownership: $console.ownership)
                            .padding(.vertical, 2)
                    } header: {
                        Text("How you have it")
                    } footer: {
                        // The rule that makes the whole feature honest, said once
                        // where it applies.
                        Text("The console's own answer. Selling it doesn't change your games, and selling the games doesn't change it.")
                    }

                    Section {
                        TextField("Model 1, OLED, modded…", text: $variant)
                    } header: {
                        Text("Which one")
                    } footer: {
                        Text("Free text on purpose — hardware variants go deep, and this is the part worth writing down.")
                    }

                    Section {
                        Toggle("Say when you got it", isOn: $knowsAcquired.animation())
                            .tint(LSTheme.accent)
                        if knowsAcquired {
                            DatePicker("Got it", selection: $acquired, displayedComponents: .date)
                        }
                    }

                    Section {
                        // Not a life someone else had — same reason the
                        // memory sheet's date fields stopped naming a
                        // Christmas and a year.
                        TextField("Anything you want to remember",
                                  text: $notes, axis: .vertical)
                            .lineLimit(2...6)
                    } header: {
                        Text("Notes")
                    }

                    Section {
                        Button(role: .destructive) { confirmingDelete = true } label: {
                            Label("Delete Console", systemImage: "trash")
                        }
                    } footer: {
                        Text("Your games stay exactly as they are. The console won't be added back from them.")
                    }

                }
                .listRowBackground(LSTheme.cardFill)
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(LSTheme.liveSheetGround)

            .navigationTitle(PlatformShort.name(console.platform))
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save(); dismiss() }
                }
            }
            .confirmationDialog("Delete this console?", isPresented: $confirmingDelete,
                                titleVisibility: .visible) {
                Button("Delete Console", role: .destructive) {
                    repo.softDelete(console)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("It goes to Recently Deleted for 30 days. Your games are untouched.")
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                variant = console.variant ?? ""
                notes = console.notes ?? ""
                knowsAcquired = console.acquiredAt != nil
                acquired = console.acquiredAt ?? .now
            }
        }
    }

    private func save() {
        repo.updateConsole(console,
                           variant: variant,
                           acquiredAt: .some(knowsAcquired ? acquired : nil),
                           notes: notes)
    }
}

/// A console on its own plate, for choosing one.
///
/// **The art is the content here, so it gets something to sit on.** A card
/// fill is 6% white in dark mode and a Switch 2, a Steam Deck and a PS4 are
/// all essentially black — Tim, 2026-09-08: *"the color is a bit dark behind
/// them, so there's not enough contrast between some of the consoles and the
/// sheet."* This is a lit shelf rather than a flat card: brighter at the top
/// where a product photo's light comes from, so a black console has an edge
/// against it in either theme.
struct ConsolePlateTile: View {
    let platform: String
    var size: CGFloat = 58
    var isSelected = false

    private var plate: LinearGradient {
        LinearGradient(colors: [
            .lsDynamic(light: .black.opacity(0.04), dark: .white.opacity(0.17)),
            .lsDynamic(light: .black.opacity(0.09), dark: .white.opacity(0.08)),
        ], startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        VStack(spacing: 6) {
            PlatformIconView(platform: platform, size: size)
                .frame(maxWidth: .infinity)
                .frame(height: size * 1.34)
            Text(PlatformShort.name(platform))
                .font(.caption.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .background(plate, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(isSelected ? LSTheme.accentFill : LSTheme.hairline,
                          lineWidth: isSelected ? 2.5 : 1))
        .overlay(alignment: .topTrailing) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.subheadline)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(LSTheme.onAccent, LSTheme.accentFill)
                    .padding(7)
            }
        }
    }
}

/// Add a console you own, with or without games on it.
///
/// The Dreamcast in the display case that the computed shelf could never
/// show, because it was computed from games.
///
/// **A grid, not a list.** A row of names with a thumbnail beside it makes the
/// name the thing you read and the console the decoration, which is backwards
/// for a picker whose whole subject is the hardware — Tim: *"this could be a
/// bit bigger of a grid, maybe even the 3 across… instead of having it be so
/// much of a name focused list."* Three across is the case's own shape, so
/// choosing a console looks like the shelf it is about to join.
struct AddConsoleSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    @Query(filter: #Predicate<Console> { $0.deletedAt == nil }) private var consoles: [Console]
    @State private var search = ""
    /// **Several at once.** Somebody setting the app up has a shelf of
    /// consoles, not one, and adding them one at a time means the sheet opens
    /// and closes for each. Tim, 2026-09-08: *"Can we let users tap to select
    /// multiple consoles to add them in one go?"*
    @State private var picked: Set<String> = []

    private var repo: Repository { Repository(context) }

    private var wide: Bool {
        #if os(macOS)
        true
        #else
        sizeClass == .regular
        #endif
    }

    private var columns: [GridItem] {
        let count = typeSize.isAccessibilitySize ? (wide ? 3 : 2) : (wide ? 5 : 3)
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: count)
    }

    /// Everything the catalogue knows, minus what you already have.
    private var options: [String] {
        let have = Set(consoles.map(\.platform))
        var seen = Set<String>()
        return PlatformCatalog.all
            // **A storefront is not a console.** itch.io belongs in the
            // catalogue — it is the one platform whose games routinely have
            // no IGDB entry, so a game has to be nameable as itch.io — but
            // this sheet is a shelf of hardware you own, and you do not own an
            // itch.io. Tim: *"Not sure what to do with itch either. It's not a
            // device."*
            .filter { PlatformIcon.assetName($0) != nil }
            .filter { !have.contains(PlatformKey.canonical($0)) }
            .filter { seen.insert(PlatformKey.canonical($0)).inserted }
            .filter { search.isEmpty || PlatformShort.name($0).localizedCaseInsensitiveContains(search) }
    }

    /// **By maker, alphabetically; inside each, oldest first.**
    ///
    /// The catalogue's own order was a hand-written list, and any hand-written
    /// list is a claim about what matters most — this one opened with Switch 2
    /// because that is what its author plays. Tim: *"That way it's not
    /// opinionated in any way."* Alphabetical needs no defending, and
    /// chronology inside a maker is the shelf a company actually built.
    private var grouped: [(maker: String, platforms: [String])] {
        var byMaker: [String: [String]] = [:]
        for platform in options {
            // A platform with no maker recorded is named for itself rather
            // than dropped — the picker must never quietly omit something the
            // catalogue offers.
            let maker = PlatformMaker.of(platform) ?? PlatformShort.name(platform)
            byMaker[maker, default: []].append(platform)
        }
        return byMaker
            .map { maker, platforms in
                (maker: maker, platforms: platforms.sorted {
                    let a = PlatformEra.releaseYear($0) ?? Int.max
                    let b = PlatformEra.releaseYear($1) ?? Int.max
                    return a == b
                        ? PlatformShort.name($0) < PlatformShort.name($1)
                        : a < b
                })
            }
            .sorted { $0.maker.localizedCaseInsensitiveCompare($1.maker) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(grouped, id: \.maker) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.maker)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                            LazyVGrid(columns: columns, spacing: 10) {
                                ForEach(group.platforms, id: \.self) { platform in
                                    Button {
                                        if picked.contains(platform) { picked.remove(platform) }
                                        else { picked.insert(platform) }
                                    } label: {
                                        ConsolePlateTile(platform: platform,
                                                         isSelected: picked.contains(platform))
                                    }
                                    .buttonStyle(PressableCardStyle())
                                    .accessibilityLabel(PlatformShort.name(platform))
                                    .accessibilityAddTraits(picked.contains(platform) ? .isSelected : [])
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
            }
            .scrollIndicators(.hidden)
            .background(LSTheme.liveSheetGround)
            .searchable(text: $search, prompt: "Search consoles")
            .navigationTitle("Add a console")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(picked.count > 1 ? "Add \(picked.count)" : "Add") {
                        // In the order they are shown rather than the order
                        // they were tapped, so a shelf added in one go lands
                        // in the order the picker just presented.
                        for group in grouped {
                            for platform in group.platforms where picked.contains(platform) {
                                repo.addConsole(platform: platform)
                            }
                        }
                        dismiss()
                    }
                    .disabled(picked.isEmpty)
                }
            }
            .overlay {
                if options.isEmpty && search.isEmpty {
                    ContentUnavailableView("Nothing left to add",
                                           systemImage: "checkmark.circle",
                                           description: Text("Every console the app knows about is already yours."))
                }
            }
        }
    }
}
