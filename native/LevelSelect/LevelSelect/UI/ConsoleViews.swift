import SwiftUI
import SwiftData
import PhotosUI

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
    @Environment(\.dynamicTypeSize) private var typeSize
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

    /// **Your photograph wins over the render.** The render is a stand-in for
    /// a machine the app has never seen; once you have shown it the actual
    /// one, drawing the stand-in beside it would be strange. Newest first here
    /// rather than oldest, because the most recent picture is the shelf as it
    /// looks now.
    private func photo(_ console: Console) -> GameImage? {
        (console.images ?? [])
            .filter { $0.deletedAt == nil && $0.data != nil }
            .max { $0.addedAt < $1.addedAt }
    }

    /// Read once per body rather than per row — the settings fetch is cheap
    /// but it is not free, and a lineage of four would do it four times.
    private var variantMap: [String: String] {
        ThemePalette.fetchOrCreate(in: context).platformIconVariants
    }

    private func summary(_ console: Console) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // **Half the width to the machine.** Tim's markup on the mockup,
            // 2026-09-08: *"Expand the console image to half width."* The
            // plate held the icon at 40pt beside a stack of text, which made
            // the console a bullet point on a page about itself. At this size
            // it is the subject and the facts read beside it — and when there
            // is a photograph, the photograph takes the plate outright,
            // because the render was only ever standing in for the machine.
            // **A brand-new console has almost nothing to say.** No model, no
            // date, maybe no games — and half a card of empty rows beside a
            // picture reads as something failing to load. Under two facts the
            // machine takes the whole width and the one fact sits under it;
            // filling the record in is what splits the card.
            let rows = facts(console)
            // **The split needs room the largest text sizes do not leave.** At
            // AX XXXL the right column is under half a phone, and a caption
            // there truncated "Model" to "M…" and broke "Games" across two
            // lines mid-word. Same answer as too few facts: stack it.
            if rows.count < 2 || typeSize.isAccessibilitySize {
                machine(console)
                    .frame(maxWidth: .infinity)
                    .frame(height: 132)
                factRows(rows)
            } else {
                HStack(alignment: .center, spacing: 14) {
                    machine(console)
                        .frame(maxWidth: .infinity)
                        .frame(height: 132)
                    factRows(rows)
                        .frame(maxWidth: .infinity)
                }
            }

            if !console.ownership.isEmpty {
                // Read-only here. The chips that SET ownership live in the
                // editor this card opens; two sets of chips that look alike
                // and behave differently would be the worse problem.
                FlowLayout(spacing: 6) {
                    ForEach(console.ownership.compactMap { Ownership(rawValue: $0) }, id: \.self) { own in
                        HStack(spacing: 4) {
                            Image(systemName: own.systemImage)
                            Text(own.label)
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(LSTheme.accent)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(LSTheme.accent.opacity(0.16), in: .capsule)
                    }
                }
            } else {
                Text("Tap to say how you have it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let detail = detail(console) {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // **The machines you have had, oldest first.** One is just the
            // icon again, so the row appears at two — a lineage needs a line.
            let lineage = PlatformVariant.owned(for: platform, in: variantMap)
            if lineage.count > 1 {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Machines you have had")
                        .font(.caption2)
                        // `.tertiary` all but disappeared on the light ground
                        // — it reads on charcoal and not on lavender. Same
                        // weight as the line above it now.
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(lineage) { option in
                            VStack(spacing: 3) {
                                VariantThumb(asset: option.asset
                                             ?? PlatformIcon.assetName(platform))
                                Text(option.label)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .frame(maxWidth: 62)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(12)
        .background(LSTheme.cardFill, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(LSTheme.hairline))
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Edit this console")
    }

    /// The labelled rows, beside the machine or under it.
    private func factRows(_ rows: [(key: String, value: String)]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, fact in
                if index > 0 { Divider().overlay(LSTheme.hairline) }
                // Key over value once the text is large, side by side below
                // that — the pattern a Settings row follows, and for the same
                // reason: two pieces of text cannot share a line they no
                // longer both fit on.
                let stacked = typeSize.isAccessibilitySize
                ViewThatFits(in: .horizontal) {
                    if !stacked {
                        HStack(spacing: 8) {
                            Text(fact.key)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            Text(fact.value)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(fact.key)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(fact.value)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 7)
            }
        }
    }

    /// The photograph if there is one, the render if there is not.
    @ViewBuilder
    private func machine(_ console: Console) -> some View {
        if let data = photo(console)?.data {
            LocalArtworkThumb(data: data, contentMode: .fill)
                .clipShape(.rect(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(LSTheme.hairline))
        } else {
            PlatformIconView(platform: platform, size: 108)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    // The same lit plate the picker's tiles use, so the
                    // machine sits on the surface it does everywhere else.
                    LinearGradient(colors: [
                        .lsDynamic(light: .black.opacity(0.04), dark: .white.opacity(0.17)),
                        .lsDynamic(light: .black.opacity(0.09), dark: .white.opacity(0.08)),
                    ], startPoint: .top, endPoint: .bottom),
                    in: .rect(cornerRadius: 12))
        }
    }

    /// **Only the facts this console actually has.** An empty "Since" row is
    /// a question the page is asking you rather than an answer it is giving,
    /// and four rows of dashes beside a picture reads as a broken record.
    private func facts(_ console: Console) -> [(key: String, value: String)] {
        var out: [(String, String)] = []
        if let variant = console.variant, !variant.isEmpty {
            out.append(("Model", variant))
        }
        if let acquired = console.acquiredAt {
            out.append(("Since", acquired.formatted(.dateTime.year())))
        }
        let mine = games.filter {
            $0.deletedAt == nil && $0.status != .wishlist
                && PlatformRoute.matches($0, platform: platform, ownership: nil)
        }
        out.append(("Games", "\(mine.count)"))
        let played = mine.reduce(0.0) { $0 + $1.lifetimePlaytime() }
        if played > 0 { out.append(("Played", Format.hours(played))) }
        return out
    }

    /// **Your note, and only your note.**
    ///
    /// This used to read "Model 1 · since 1994 · my brother's", because the
    /// card had one line for everything the record held. `facts` now says the
    /// model and the year in labelled rows beside the machine, so repeating
    /// them here printed "Model 1" twice on the same card.
    private func detail(_ console: Console) -> String? {
        guard let notes = console.notes, !notes.isEmpty else { return nil }
        return notes
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
    @State private var photoItem: PhotosPickerItem?
    @State private var importing = false
    @State private var importError: String?
    @State private var removingPhoto: GameImage?

    private var repo: Repository { Repository(context) }

    var body: some View {
        NavigationStack {
            Form {
                // The app's own card fill, so the rows keep the theme at any
                // detent — see `SettingsPage` for why the system's gray drains.
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

                    // **The shell the app draws.** Separate from the free text
                    // above, which is anything you want to record; this is the
                    // short list the app has a picture for. It appears only for
                    // consoles that HAVE more than one, so most machines show
                    // no choice at all rather than a control with one option.
                    if variants.count > 1 {
                        Section {
                            ForEach(variants) { option in
                                Button { choose(option) } label: {
                                    HStack(spacing: 12) {
                                        VariantThumb(asset: option.asset
                                                     ?? PlatformIcon.assetName(console.platform))
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(option.label).foregroundStyle(.primary)
                                            Text(option.detail)
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 0)
                                        if option.key == chosenVariantKey {
                                            Image(systemName: "checkmark")
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(LSTheme.accent)
                                        }
                                    }
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                            }
                        } header: {
                            Text("Which one to draw")
                        } footer: {
                            Text("Changes the picture everywhere this console appears.")
                        }

                        // **Thirty years of one platform is several machines.**
                        // Tim, 2026-09-09: *"if someone's gonna be gaming for
                        // 30 years maybe they owned a Mac from the 80s the 90s
                        // 2000s and now and they would want to have those all
                        // represented on the console page."* The tile has one
                        // icon slot and always will; the page has room for the
                        // lineage. Two questions, so two lists, rather than one
                        // control quietly answering both.
                        Section {
                            ForEach(variants) { option in
                                Button { toggleHad(option) } label: {
                                    HStack(spacing: 12) {
                                        VariantThumb(asset: option.asset
                                                     ?? PlatformIcon.assetName(console.platform))
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(option.label).foregroundStyle(.primary)
                                            Text(option.detail)
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: hadKeys.contains(option.key)
                                              || option.key == chosenVariantKey
                                              ? "checkmark.circle.fill" : "circle")
                                            .font(.title3)
                                            .foregroundStyle(hadKeys.contains(option.key)
                                                             || option.key == chosenVariantKey
                                                             ? LSTheme.accent : .secondary)
                                    }
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                                .disabled(option.key == chosenVariantKey)
                            }
                        } header: {
                            Text("Machines you have had")
                        } footer: {
                            Text("Shown as a row on this console's page. The one you draw is always included.")
                        }
                    }

                    Section {
                        if !photos.isEmpty {
                            ScrollView(.horizontal) {
                                HStack(spacing: 8) {
                                    ForEach(photos) { photo in
                                        // `data` is optional on GameImage —
                                        // external storage means the bytes can
                                        // still be arriving from CloudKit.
                                        LocalArtworkThumb(data: photo.data ?? Data(),
                                                          contentMode: .fill)
                                            .frame(width: 96, height: 96)
                                            .clipShape(.rect(cornerRadius: 12))
                                            .contextMenu {
                                                Button(role: .destructive) {
                                                    removingPhoto = photo
                                                } label: {
                                                    Label("Remove Photo", systemImage: "trash")
                                                }
                                            }
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                            .scrollIndicators(.hidden)
                        }
                        PhotosPicker(selection: $photoItem, matching: .images,
                                     photoLibrary: .shared()) {
                            if importing {
                                HStack(spacing: 6) { ProgressView(); Text("Adding…") }
                            } else {
                                Label(photos.isEmpty ? "Add a photo" : "Add another",
                                      systemImage: "photo.badge.plus")
                            }
                        }
                        .disabled(importing)
                        if let importError {
                            Text(importError).font(.caption).foregroundStyle(.red)
                        }
                    } header: {
                        Text("Photos")
                    } footer: {
                        // The reason the feature exists, said once where it lands.
                        Text("The machine as it actually sits in your room. Downscaled and kept in your own iCloud, like every other picture you add.")
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

            .task(id: photoItem) { await ingestPickedPhoto() }
            .confirmationDialog("Remove this photo?",
                                isPresented: Binding(get: { removingPhoto != nil },
                                                     set: { if !$0 { removingPhoto = nil } }),
                                titleVisibility: .visible) {
                Button("Remove Photo", role: .destructive) {
                    if let photo = removingPhoto {
                        Repository(context).removeImage(photo, from: console)
                    }
                    removingPhoto = nil
                }
                Button("Cancel", role: .cancel) { removingPhoto = nil }
            } message: {
                Text("It is deleted rather than kept in Recently Deleted — the bytes are the point of removing it.")
            }
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

    // MARK: Which one to draw

    private var variants: [PlatformVariant.Variant] {
        PlatformVariant.variants(for: console.platform)
    }

    /// The key currently in force, resolved rather than read raw — a stored
    /// key this build has no art for reads as the default, which is what the
    /// picker should show a checkmark against.
    private var chosenVariantKey: String? {
        let stored = ThemePalette.fetchOrCreate(in: context)
            .platformIconVariants[PlatformKey.canonical(console.platform)]
        return PlatformVariant.variant(for: console.platform, key: stored)?.key
    }

    /// Written to the settings row, not to the console — the choice is "which
    /// Saturn does this library draw", and a library holds one console per
    /// platform, so the two are the same statement said in the cheaper place.
    /// It also means the picture is right on a game's chip and in the Library's
    /// filter, where there is no console record in scope at all.
    private func choose(_ option: PlatformVariant.Variant) {
        let settings = ThemePalette.fetchOrCreate(in: context)
        var map = settings.platformIconVariants
        let key = PlatformKey.canonical(console.platform)
        // The default is stored as an ABSENCE. Writing "na" would pin the
        // library to today's default, so re-commissioning the main render
        // later would leave this console pointing at the old one.
        if option.key == variants.first?.key { map.removeValue(forKey: key) }
        else { map[key] = option.key }
        settings.platformIconVariants = map
        settings.updatedAt = .now
        // The same three steps a rename takes, and for the same reason:
        // setting the static alone changes no view, because nothing observes
        // it. The commit is what redraws the tiles already on screen, and
        // `refresh` is what pushes the new map into the drawing layer.
        PersistenceMonitor.shared.commit(context)
        ThemePalette.refresh(from: settings)
        // Widgets read a snapshot, not the store.
        WidgetBridge.refresh()
    }

    /// What is ticked, not counting the drawn one — that is added at read
    /// time so unticking it is impossible rather than merely discouraged.
    private var hadKeys: Set<String> {
        PlatformVariant.ownedKeys(for: console.platform,
                                  in: ThemePalette.fetchOrCreate(in: context).platformIconVariants)
    }

    private func toggleHad(_ option: PlatformVariant.Variant) {
        let settings = ThemePalette.fetchOrCreate(in: context)
        var map = settings.platformIconVariants
        var keys = PlatformVariant.ownedKeys(for: console.platform, in: map)
        if keys.contains(option.key) { keys.remove(option.key) } else { keys.insert(option.key) }
        PlatformVariant.setOwned(keys, for: console.platform, in: &map)
        settings.platformIconVariants = map
        settings.updatedAt = .now
        PersistenceMonitor.shared.commit(context)
        ThemePalette.refresh(from: settings)
    }

    // MARK: Photos

    /// Newest last, the order they were added — a shelf of pictures reads as a
    /// sequence, not a feed.
    private var photos: [GameImage] {
        (console.images ?? [])
            .filter { $0.deletedAt == nil }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private func ingestPickedPhoto() async {
        guard let photoItem else { return }
        importing = true
        importError = nil
        defer { importing = false; self.photoItem = nil }
        do {
            guard let raw = try await photoItem.loadTransferable(type: Data.self) else {
                importError = "That photo couldn't be read."
                return
            }
            try repo.addImage(to: console, data: raw)
        } catch ImageIngest.Failure.unreadable {
            importError = "That file isn't an image this device can read."
        } catch {
            importError = "Couldn't add that picture."
        }
    }
}

/// The small render beside a model in the picker. Its own view because the
/// picker draws a SPECIFIC asset rather than "whatever this platform draws" —
/// which is the one place `PlatformIconView` cannot help, since choosing is
/// exactly the act of disagreeing with it.
struct VariantThumb: View {
    let asset: String?

    var body: some View {
        Group {
            if let asset {
                Image(asset).resizable().scaledToFit()
                    .shadow(color: .black.opacity(0.5), radius: 2.4, y: 1.9)
            } else {
                Image(systemName: "gamecontroller.fill")
                    .resizable().scaledToFit()
                    .foregroundStyle(LSTheme.accent)
                    .padding(7)
            }
        }
        .frame(width: 42, height: 42)
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
    /// **Sized to the plate, not to a menu row.** 58pt was `PlatformIconView`'s
    /// own default, carried over when this tile was written — and a square
    /// that small left a wide console using barely half the plate's width,
    /// which read as a small picture floating in a big card. Tim, 2026-09-08:
    /// *"The consoles should be a bit bigger and sit centered in the plate
    /// with the text being below that."*
    var size: CGFloat = 84
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
                // **One height for every console, and the art centered in
                // it.** The box used to be 1.34× the icon — air above and
                // below — while the label took whatever lines it needed, so a
                // two-word console stood on a shorter plate than "Neo Geo
                // Pocket Color" and the tall MVS cabinet floated with a gap
                // under it. Tim: *"I'd rather the console sit closer to the
                // text so the plate can stay the same size as the others."*
                // The two lines below are always reserved and this box is the
                // icon's own square, so every plate measures the same and the
                // picture sits in the middle of what is left above the name.
                .frame(height: size)
            Text(PlatformShort.name(platform))
                .font(.caption.weight(.medium))
                // Two lines, reserved whether or not the name needs them.
                // Also the fix for a name that truncated instead of wrapping:
                // inside a Button in a grid cell the label is offered a
                // one-line height and cuts itself to fit, which turned "Neo
                // Geo Pocket Color" into "Neo Geo Pocket…" — a different
                // handheld.
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
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
            //
            // Asked directly, rather than through "has no art". Those gave the
            // same answer only while itch.io happened to be undrawable, and
            // the moment it got a logo the accident would have put it back in
            // the grid. A console with no art yet is still a console.
            .filter { !PlatformIcon.isStorefront($0) }
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
