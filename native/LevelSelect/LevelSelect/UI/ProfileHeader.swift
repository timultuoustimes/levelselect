import SwiftUI
import SwiftData
import PhotosUI

/// The person Home belongs to.
///
/// Home is the app's one plural page — many games, several statuses, no single
/// piece of art to build it around. The audit's answer to that was shelf
/// geometry; Tim's was better: the thing uniting a plural page is **whose it
/// is**. This is that, said once at the top.
///
/// It shows only what someone actually put there. No avatar and no name means
/// no header at all, because a placeholder ring above "Add your name" is a
/// form, and a form is the opposite of a personal page.
struct ProfileHeader: View {
    let profile: PlayerProfile?
    let summary: PlayerSummary
    /// Extra art drawn ABOVE the header's own top edge, so it reaches up
    /// behind the toolbar. Home passes the top safe-area inset.
    var topOverscan: CGFloat = 0
    var onEdit: () -> Void

    private var hasAnything: Bool {
        guard let profile else { return false }
        return profile.avatarData != nil
            || profile.resolvedDisplayName != nil
            || !profile.handles.isEmpty
    }

    /// Grown from 168 on Tim's read that the art wanted to be bigger. Most of
    /// the increase is in the COVER WIDTH below rather than here: the Play
    /// button already lands well, and height here comes straight out of the
    /// Continue Playing card's position.
    private static let artHeight: CGFloat = 190
    private static let portrait: CGFloat = 84

    /// No art means no art band. Reserving the full height for a flat tint
    /// gives a new user — or anyone who hasn't played in a week — 168pt of
    /// empty color above their own name, which reads as a broken image
    /// rather than a quiet week.
    private var hasArt: Bool { Self.drawsArt(profile: profile, summary: summary) }

    /// Whether the header will paint art to its own top edge.
    ///
    /// Home asks before laying out, because that art has to bleed into the
    /// space under the toolbar. Left with the stack's ordinary top padding it
    /// sits in a 16pt trench, which reads as a misaligned image rather than a
    /// header.
    static func drawsArt(profile: PlayerProfile?, summary: PlayerSummary) -> Bool {
        guard let profile else { return false }
        let filled = profile.avatarData != nil
            || profile.resolvedDisplayName != nil
            || !profile.handles.isEmpty
        guard filled else { return false }
        return summary.usesRibbon || summary.fallbackBackdrop != nil
    }

    var body: some View {
        if let profile, hasAnything {
            VStack(spacing: 10) {
                if hasArt {
                    ZStack(alignment: .bottomLeading) {
                        backdrop
                        identity(profile)
                            .padding(.bottom, 10)
                    }
                    // NO negative top padding here, deliberately.
                    //
                    // Home's scroll view already ignores the top safe area, so
                    // content starts at the window's top edge; the band being
                    // `artHeight + topOverscan` tall is what puts the art under
                    // the toolbar, and it lands the identity row at exactly the
                    // height it had before. Offsetting as well double-counted
                    // the inset and pulled the portrait and name up into the
                    // wordmark.
                } else {
                    identity(profile)
                        .padding(.top, 4)
                }
                statBand
            }
            .contentShape(.rect)
            .onTapGesture(perform: onEdit)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityText(profile))
            .accessibilityAddTraits(.isButton)
        }
    }

    private func identity(_ profile: PlayerProfile) -> some View {
        HStack(alignment: .bottom, spacing: 12) {
            avatar(profile)
            VStack(alignment: .leading, spacing: 6) {
                if let name = profile.resolvedDisplayName {
                    // Press Start 2P — the app's own face, used somewhere
                    // other than the wordmark for the first time.
                    //
                    // It is monospaced at roughly one em per character, so a
                    // name's width is almost exactly `count x size`. Tim's
                    // "TIMULTUOUSTIMES" is 15 characters: at 22pt that is
                    // ~330pt against ~290pt of usable width beside an 84pt
                    // portrait, so it MUST be allowed to shrink. It scales to
                    // about 19pt and fits; a 24-character name lands near the
                    // 0.5 floor and stops there rather than wrapping mid-word,
                    // which is what a pixel face does worst.
                    let ink = ProfileNameColor.resolve(profile.nameColorRaw ?? "")
                    Text(name)
                        .foregroundStyle(ink)
                        .font(LSTheme.pixel(22))
                        .fontDesign(nil)   // never let an app-wide design override the pixel face
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        // The wordmark's treatment, not a new one.
                        //
                        // A soft blur under pixel type fights the face — the
                        // letterforms have hard square edges and a gaussian
                        // halo smears them, which was tolerable on a dark
                        // ground and obvious on a light one. `Wordmark` had
                        // already solved this: a hard offset in a darkened
                        // version of the ink, so the shadow reads as a second
                        // set of pixels rather than a glow. This is the only
                        // other pixel-type string in the app, and the only
                        // other place the treatment belongs — the rest of the
                        // interface is ordinary text and would just get loud.
                        // The ink darkened, so a custom name colour gets a
                        // shadow that belongs to it rather than a fixed brown
                        // — the rule `Wordmark.shadowTint` already follows.
                        // y:2, not 3. The face draws on a pixel grid, and an
                        // offset larger than one of its blocks leaves a lit
                        // gap between glyph and shadow instead of a solid
                        // step — visible at 22pt, which is far larger than
                        // the wordmark usually renders.
                        .shadow(color: ink.mix(with: .black, by: 0.55), radius: 0, y: 2)
                }
                handleChips(profile)
            }
            .padding(.bottom, 2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
    }

    /// Your week, or one game.
    ///
    /// The ribbon is the covers of everything played in the last seven days,
    /// tilted and dimmed — so the header genuinely changes because of how you
    /// played, without anyone choosing anything. Under three games it stops
    /// reading as a pattern, so it falls back to a single game's artwork,
    /// which is a composition rather than a gap.
    @ViewBuilder
    private var backdrop: some View {
        GeometryReader { geo in
            Group {
                if summary.usesRibbon {
                    ribbon(width: geo.size.width)
                } else if let art = summary.fallbackBackdrop {
                    CoverThumb(urlString: art)
                        .frame(width: geo.size.width, height: (Self.artHeight + topOverscan) * 1.7)
                        .clipped()
                        .blur(radius: 3)
                        .opacity(0.55)
                }
            }
            .frame(width: geo.size.width, height: Self.artHeight + topOverscan)
            .clipped()
        }
        .frame(height: Self.artHeight + topOverscan)
        // A MASK, not a color overlay — the same technique the game page
        // uses. Painting the page color on top would be wrong the moment
        // someone changes their page background, since the header would then
        // fade to a color the page no longer is.
        //
        // Holds through the top half and clears by the bottom, so the portrait
        // and the name sit on the page rather than on the art.
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.38),
                    .init(color: .black.opacity(0.45), location: 0.68),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top, endPoint: .bottom)
        }
        .accessibilityHidden(true)
    }

    /// The week's covers, sized to whatever screen they land on.
    ///
    /// Two things were wrong on iPad and both are visible in one shot.
    ///
    /// The tile was a fixed 104pt, so the ribbon's width was decided by how
    /// many games you played rather than by the screen: three covers make
    /// 327pt, which fills an iPhone and floats as a narrow block in the middle
    /// of a 1032pt iPad. The tile is now derived from the available width, so
    /// the same three covers span the iPad as three big soft panels and nine
    /// covers pack an iPhone.
    ///
    /// And `.frame(width:)` set no height, so each cover was only as tall as
    /// its own 3:4 aspect at that width — 139pt inside a 247pt row. That short
    /// fall is the hard horizontal cut across the top of the art. The height
    /// is now explicit and deliberately TALLER than the band, so every cover
    /// overshoots and the crop happens off-screen.
    private func ribbon(width: CGFloat) -> some View {
        let covers = Array(summary.recentCovers.prefix(12))
        // 1.3 of the width, because the row is rotated: the corners have to
        // come from somewhere or they cut in as diagonal notches.
        let tile = max(96, (width * 1.3) / CGFloat(max(covers.count, 1)))
        return HStack(spacing: 4) {
            ForEach(Array(covers.enumerated()), id: \.offset) { _, art in
                CoverThumb(urlString: art)
                    .frame(width: tile, height: (Self.artHeight + topOverscan) * 1.7)
                    .clipped()
            }
        }
        .rotationEffect(.degrees(-4))
        .blur(radius: 2)
        .opacity(0.5)
    }

    @ViewBuilder
    private func avatar(_ profile: PlayerProfile) -> some View {
        Group {
            if let data = profile.avatarData {
                // Uncropped. A cut-out render stands in the header the way a
                // logo stands on a game page; a circular mask would take the
                // top off anything taller than it is wide.
                LocalArtworkThumb(data: data, contentMode: .fit)
            } else if let initial = profile.resolvedDisplayName?.first {
                Text(String(initial).uppercased())
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(LSTheme.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(LSTheme.accent.opacity(0.16))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .frame(width: Self.portrait, height: Self.portrait)
        .shadow(color: .black.opacity(0.55), radius: 10, y: 5)
    }

    /// ONE handle, whatever the data looks like — and not the handle at all
    /// when the name above already IS it.
    ///
    /// Two chips side by side don't fit a phone: the first truncated to
    /// "timultuoustim…", which is worse than not showing it. The editor is
    /// where the full set lives; the header says who you are once.
    ///
    /// Shows the handle used by the MOST services, so someone with one name
    /// across Steam, Xbox and PSN plus a different Discord sees the name that
    /// is actually theirs. Any others become a count.
    @ViewBuilder
    private func handleChips(_ profile: PlayerProfile) -> some View {
        let grouped = profile.groupedHandles
            .sorted { $0.services.count > $1.services.count }
        if let main = grouped.first {
            // When the display name and the handle are the same word, printing
            // both puts it on screen twice in a row. The services alone are
            // the part that adds anything, and they read as a caption to the
            // name rather than a repeat of it.
            let echoesName = main.handle.compare(
                profile.resolvedDisplayName ?? "",
                options: .caseInsensitive) == .orderedSame

            HStack(spacing: 6) {
                // `ViewThatFits` MEASURES rather than guessing a cutoff.
                //
                // Six services wrapped to a second line and left a separator
                // dangling at the end of the first — "… Discord ·" — inside a
                // capsule that then went ragged. A fixed cap would be wrong on
                // the other side: three services have room to spare on an
                // iPhone and eleven do not fit an iPad. This tries the whole
                // list first and drops one service at a time until a version
                // fits on ONE line, folding the remainder into a count.
                ViewThatFits(in: .horizontal) {
                    ForEach(Array(stride(from: main.services.count, through: 1, by: -1)),
                            id: \.self) { shown in
                        chip(main, showing: shown, echoesName: echoesName)
                    }
                }

                if grouped.count > 1 {
                    Text("+\(grouped.count - 1)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .glassEffect(.regular, in: .capsule)
                }
            }
        }
    }

    /// One capsule showing `showing` services, with any remainder as "+N".
    private func chip(_ row: (handle: String, services: [HandleService]),
                      showing: Int, echoesName: Bool) -> some View {
        let visible = row.services.prefix(showing).map(\.label)
        let hidden = row.services.count - showing
        // The count joins the list as another item, so the separator rhythm
        // never breaks and no "·" is ever left hanging at the end.
        let text = (visible + (hidden > 0 ? ["+\(hidden)"] : []))
            .joined(separator: " · ")

        return HStack(spacing: 5) {
            Text(text)
                .foregroundStyle(echoesName ? .secondary : .tertiary)
            if !echoesName {
                Text(row.handle)
                    .foregroundStyle(.secondary)
                    .truncationMode(.tail)
            }
        }
        .font(.caption2)
        .lineLimit(1)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .glassEffect(.regular, in: .capsule)
    }

    /// Three numbers that all move.
    ///
    /// An earlier version showed four, two of which ("174 games", "5 finished")
    /// read the same week after week. A header nobody reads twice is height
    /// spent on nothing — and height here is taken directly from the Continue
    /// Playing card below.
    private var statBand: some View {
        HStack(spacing: 0) {
            stat("\(summary.playing)", "Playing")
            divider
            stat(Format.duration(summary.weekSeconds), "This week")
            divider
            stat(Format.duration(summary.totalSeconds), "Total")
        }
        // Liquid Glass rather than a flat white wash. The band sits directly
        // under the art, so it should pick up what is behind it instead of
        // laying an opaque gray slab over the bottom of the ribbon.
        .glassEffect(.regular, in: .rect(cornerRadius: 13))
        .padding(.horizontal, 16)
    }

    private var divider: some View {
        Rectangle().fill(LSTheme.separator).frame(width: 1, height: 26)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 9.5, weight: .medium))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
    }

    private func accessibilityText(_ profile: PlayerProfile) -> String {
        var parts: [String] = []
        if let name = profile.resolvedDisplayName { parts.append(name) }
        parts.append("\(summary.playing) playing")
        parts.append("\(Format.duration(summary.weekSeconds)) this week")
        parts.append("\(Format.duration(summary.totalSeconds)) total")
        return parts.joined(separator: ", ")
    }
}

/// An image waiting to be positioned. `sheet(item:)` needs identity and `Data`
/// has none of its own.
/// The editor's one sheet, as a value.
///
/// Two `.sheet` modifiers on the same view do NOT both work — SwiftUI keeps
/// one and silently drops the other, which is why "Game art" opened nothing.
/// One modifier driven by an enum is the shape that actually works.
private enum AvatarSheet: Identifiable {
    case artwork
    case memoji
    case crop(Data)

    var id: String {
        switch self {
        case .artwork: "artwork"
        case .memoji: "memoji"
        case .crop(let d): "crop-\(d.count)"
        }
    }
}

/// Editing the profile. Everything is optional and blank means absent — there
/// is nothing here to "complete".
struct ProfileEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [PlayerProfile]

    @State private var name = ""
    @State private var nameColorRaw = ""
    @State private var useHandleAsName = false
    @State private var handles: [String: String] = [:]
    @State private var picking: PhotosPickerItem?
    @State private var choosingSource = false
    /// Load from the model exactly once.
    @State private var loaded = false
    @State private var pickingPhoto = false
    /// Which sheet is up, if any. One modifier, one source of truth.
    @State private var sheet: AvatarSheet?
    @State private var avatar: Data?
    @State private var importError: String?

    private var profile: PlayerProfile? { profiles.first }

    /// Extracted from `body` because the whole Form went past the
    /// type-checker's budget — "unable to type-check this expression in
    /// reasonable time" is a size complaint, not a correctness one, and the
    /// cure is to give the largest sub-expression its own name.
    private var avatarButton: some View {
        Button { choosingSource = true } label: {
            ZStack {
                if let avatar {
                    LocalArtworkThumb(data: avatar, contentMode: .fit)
                        .frame(width: 108, height: 108)
                } else {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 78))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 116, height: 116)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "pencil")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(LSTheme.onAccent)
                    .frame(width: 28, height: 28)
                    .background(LSTheme.accent, in: .circle)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(avatar == nil ? "Add a picture" : "Change picture")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 10) {
                            // The picture IS the control. Three text buttons
                            // under it were a row of separate targets in one
                            // Form row — which hit-tested as a single control
                            // and fired the wrong one — and none of them was
                            // the thing you actually want to tap.
                            avatarButton

                            Text(avatar == nil ? "Add a picture" : "Tap to change")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                Section {
                    TextField("Your name", text: $name)
                        .disabled(useHandleAsName)
                        .foregroundStyle(useHandleAsName ? .secondary : .primary)
                    // One tap instead of retyping a handle you already
                    // entered. It COPIES rather than links — the name stays
                    // yours to edit, and changing a handle later does not
                    // silently rename you.
                    if primaryDraftHandle != nil {
                        Toggle("Use my handle as my name", isOn: $useHandleAsName)
                            .tint(LSTheme.accent)
                    }

                    if !useHandleAsName, let handle = primaryDraftHandle, handle != name {
                        Button {
                            name = handle
                        } label: {
                            Label("Use \"\(handle)\"", systemImage: "arrow.turn.up.left")
                                .font(.subheadline)
                        }
                        .buttonStyle(.borderless)
                    }
                    Picker("Name color", selection: Binding(
                        get: { ProfileNameColor.mode(of: nameColorRaw) },
                        set: { mode in
                            switch mode {
                            case .plain:  nameColorRaw = ProfileNameColor.plain
                            case .accent: nameColorRaw = ProfileNameColor.accent
                            case .custom:
                                // Seed from the accent, so "Custom" starts
                                // somewhere deliberate rather than black.
                                if ProfileNameColor.mode(of: nameColorRaw) != .custom {
                                    nameColorRaw = LSTheme.accent.hexString() ?? "#FFFFFF"
                                }
                            }
                        })) {
                        ForEach(ProfileNameColor.Mode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if ProfileNameColor.mode(of: nameColorRaw) == .custom {
                        NavigationLink {
                            ColorEditor(title: "Name color", targets: [
                                ColorTarget(
                                    id: "name", label: "Name color",
                                    defaultColor: LSTheme.accent,
                                    isCustomised: true,
                                    binding: Binding(
                                        get: { Color(hex: nameColorRaw) ?? LSTheme.accent },
                                        set: { nameColorRaw = $0.hexString() ?? nameColorRaw }),
                                    onReset: { nameColorRaw = ProfileNameColor.accent }),
                            ])
                        } label: {
                            HStack {
                                Text("Pick a color")
                                Spacer()
                                Circle()
                                    .fill(ProfileNameColor.swatch(nameColorRaw))
                                    .frame(width: 22, height: 22)
                                    .overlay { Circle().strokeBorder(LSTheme.hairline, lineWidth: 1) }
                            }
                        }
                    }
                } footer: {
                    // "Accent" is the one worth explaining: it keeps following
                    // the theme instead of freezing today's accent.
                    Text("Shown at the top of Home. Leave the name blank and nothing appears. Accent keeps the name matched to your accent color as you change it.")
                }

                Section {
                    ForEach(groupedDrafts, id: \.handle) { group in
                        NavigationLink {
                            HandleEditor(handles: $handles, existing: group.handle)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(group.handle)
                                Text(group.services.map(\.label).joined(separator: " · "))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    // Offered only while something is still unassigned. Once
                    // one handle covers every service there is nothing left to
                    // add, and a button that leads to an empty choice is just
                    // a dead end wearing a plus sign.
                    if hasUnassignedServices {
                        NavigationLink {
                            HandleEditor(handles: $handles, existing: nil)
                        } label: {
                            Label(groupedDrafts.isEmpty ? "Add a handle" : "Add another handle",
                                  systemImage: "plus")
                        }
                    }
                } header: {
                    Text("Handles")
                } footer: {
                    Text("Add a handle once and tick everywhere you use it. Signing up somewhere new later means opening that handle and adding the service — not typing it again. These are decoration: nothing signs in and nothing is shared.")
                }

                if let importError {
                    Text(importError)
                        .font(.footnote)
                        .foregroundStyle(LSTheme.working)
                }
            }
            #if os(macOS)
            .formStyle(.grouped)
            #endif
            .navigationTitle("Your profile")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save(); dismiss() }
                }
            }
            .task { load() }
            .task(id: picking) { await ingest() }
            // One menu, naming the three places a picture can come from.
            .confirmationDialog("Profile picture", isPresented: $choosingSource,
                                titleVisibility: .visible) {
                Button("Choose a photo") { pickingPhoto = true }
                Button("Choose game art") { sheet = .artwork }
                #if os(iOS)
                Button("Choose a sticker or Memoji") { sheet = .memoji }
                #endif
                if avatar != nil {
                    Button("Remove picture", role: .destructive) { avatar = nil }
                }
                Button("Cancel", role: .cancel) {}
            }
            .photosPicker(isPresented: $pickingPhoto, selection: $picking, matching: .images)
            .sheet(item: $sheet) { which in
                switch which {
                case .artwork:
                    AvatarArtworkPicker { take($0) }
                case .memoji:
                    #if os(iOS)
                    // Stickers arrive as transparent HEIC, so `take` sends
                    // them straight through with no crop step — which is
                    // right: a sticker is already a cut-out of one thing.
                    NavigationStack { StickerPicker { take($0) } }
                    #else
                    EmptyView()
                    #endif
                case .crop(let raw):
                    AvatarCropView(source: raw) { take($0, alreadyCropped: true) }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 520)
        #endif
    }

    /// The handle covering the most services — the one most likely to be
    /// what someone would call themselves.
    private var primaryDraftHandle: String? {
        groupedDrafts.max { $0.services.count < $1.services.count }?.handle
    }

    /// The drafts as they will be DRAWN — one row per distinct handle.
    private var groupedDrafts: [(handle: String, services: [HandleService])] {
        Dictionary(grouping: handles.keys.compactMap(HandleService.init(key:))) {
            handles[$0.key] ?? ""
        }
        .filter { !$0.key.isEmpty }
        .map { (handle: $0.key, services: $0.value.sorted { $0.order < $1.order }) }
        .sorted { ($0.services.first?.order ?? 0) < ($1.services.first?.order ?? 0) }
    }

    private var hasUnassignedServices: Bool {
        let used = Set(handles.keys)
        return HandleService.builtins.contains { !used.contains($0.key) }
    }

    /// The one rule that decides how an avatar behaves, applied in one place.
    ///
    /// **Transparency present** — a cut-out PNG, a Memoji, a logo-shaped piece
    /// of game art — goes straight in and is drawn whole and unframed, the way
    /// a logo sits on a game page. There is nothing to crop: the image is
    /// already the subject and nothing else.
    ///
    /// **Opaque** — a photo, or a wide painting of a whole scene — gets the
    /// positioning step, because something has to choose which square of a
    /// 16:9 image survives and the person is better at that than a center
    /// crop. The character is rarely in the middle.
    ///
    /// Nobody is asked which of these they want. The image already knows.
    private func take(_ raw: Data, alreadyCropped: Bool = false) {
        if !alreadyCropped && !ImageIngest.hasAlpha(raw) {
            // Replacing the source sheet with the crop sheet, not stacking
            // one on the other.
            sheet = .crop(raw)
            return
        }
        do {
            avatar = try ImageIngest.prepareAvatar(raw).data
            importError = nil
        } catch {
            importError = "That picture couldn't be used. Try another."
        }
        sheet = nil
    }

    /// Fill the drafts from the stored profile — ONCE.
    ///
    /// `.task` runs again when this view returns to the screen, and pushing
    /// the handle editor and coming back is exactly that. Without the guard
    /// it reloaded from the model on the way back and threw away everything
    /// just typed: handles were added, Done was tapped, and nothing saved.
    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let profile else { return }
        name = profile.displayName ?? ""
        handles = profile.handles
        avatar = profile.avatarData
        useHandleAsName = profile.useHandleAsName
        // Carry across whatever was chosen while this lived on the device
        // only, so nobody has to set it twice.
        nameColorRaw = profile.nameColorRaw
            ?? UserDefaults.standard.string(forKey: ProfileNameColor.key)
            ?? ProfileNameColor.plain
    }

    private func ingest() async {
        guard let picking else { return }
        importError = nil
        do {
            guard let raw = try await picking.loadTransferable(type: Data.self) else { return }
            // Same downscaler the artwork picker uses. An avatar drawn at 52pt
            // has no business carrying a camera's output, and keeping it small
            // is what lets `avatarData` be a plain inline field.
            take(raw)
        } catch {
            importError = "That picture couldn't be used. Try another."
        }
    }

    private func save() {
        let target: PlayerProfile
        if let profile {
            target = profile
        } else {
            target = PlayerProfile()
            context.insert(target)
        }
        target.displayName = name.trimmingCharacters(in: .whitespaces).isEmpty ? nil : name
        target.nameColorRaw = nameColorRaw.isEmpty ? nil : nameColorRaw
        target.useHandleAsName = useHandleAsName
        target.avatarData = avatar
        target.handles = handles
        target.updatedAt = .now
        PersistenceMonitor.shared.commit(context)
    }
}
