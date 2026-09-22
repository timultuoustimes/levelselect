import SwiftUI
#if canImport(LinkPresentation)
import LinkPresentation
#endif
import SwiftData
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// **A period of your own library, read back to you.**
///
/// Not another list of numbers — the Charts lens is already that, and it is
/// the surface this was specced beside. A Replay is a designed artifact you
/// open, look at, and close, which is why it is a card there rather than a
/// fifth lens: it is an occasion, not a place you live.
///
/// **Rebuilt to Fable's mockup (09-21)**, which drew the three cases the
/// runtime assessment found wrong — a month one game led, a year nothing
/// dominated, a year with one finish and no play — and what would earn each
/// an App Store slot:
///
/// - **The box art is the hero.** One game's cover full bleed when a game led
///   the period or a finish is its story; a mosaic of the leaders when
///   nothing did. That is what reads at thumbnail size in a store carousel,
///   and it makes every library's year look like that library.
/// - **The screen says its name** — "Replay", in the pixel face — instead of
///   the bar repeating whichever chip is selected.
/// - **The chips are pinned** under the bar and fade at the edge, so the row
///   reads as scrollable and the span changes from anywhere on the page.
/// - **Stats are one quiet line**, which wraps between words at the largest
///   text sizes where three pills broke mid-syllable.
/// - **Save as image** renders the page without its chrome. Nothing is
///   uploaded; it is also how the store screenshot gets made.
///
/// Everything on it is computed on the device from records already in the
/// store. Nothing is sent anywhere to make it.
struct ReplayView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var spans: [Replay.Span] = []
    @State private var chosen = 0
    @State private var replay: Replay?
    @State private var games: [UUID: Game] = [:]
    @State private var exportURL: ExportedImage?
    @State private var exporting = false

    /// A rendered page waiting for the share sheet — the file for the Mac's
    /// save panel, the picture itself on iOS so "Save Image" puts it in Photos.
    struct ExportedImage: Identifiable {
        let url: URL
        #if canImport(UIKit)
        let image: UIImage
        #endif
        var id: URL { url }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let replay, replay.offersOwnPage || replay.span == .beforeTracking {
                        ReplayPage(replay: replay, games: games) {
                            // "+N" opens the whole ledger, in the Journal.
                            dismiss()
                            AppNavigator.shared.journalLens = "badges"
                        }
                        saveButton
                    } else {
                        empty
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                // Room past the last card: on the iPad's form sheet the page
                // ended flush with the sheet's edge and clipped it (Fable).
                .padding(.bottom, 48)
            }
            .scrollIndicators(.hidden)
            .safeAreaBar(edge: .top) {
                if spans.count > 1 { chips }
            }
            .lsBackground()
            .toolbar {
                ToolbarItem(placement: Self.namePlacement) {
                    Text("Replay")
                        .font(LSTheme.pixel(19))
                        .foregroundStyle(LSTheme.accent)
                        .lineLimit(1)
                        .fixedSize()
                        .accessibilityAddTraits(.isHeader)
                }
                // A name, not a control: without this iOS 26 wrapped it in a
                // glass capsule too narrow for it, and it read "…". The Home
                // wordmark had the same fix for the same reason.
                #if os(iOS)
                .sharedBackgroundVisibility(.hidden)
                #endif
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .task {
            spans = ReplayBuilder.availableSpans(in: context)
            rebuild()
        }
        .onChange(of: chosen) { _, _ in rebuild() }
        .sheet(item: $exportURL) { export in
            #if canImport(UIKit)
            ImageShareSheet(image: export.image, title: export.url.deletingPathExtension().lastPathComponent)
            #else
            ShareSheet(url: export.url)
            #endif
        }
    }

    private static var namePlacement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .navigation
        #endif
    }

    private func rebuild() {
        let source = ReplayBuilder.source(in: context)
        games = Dictionary(source.games.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        guard spans.indices.contains(chosen) else {
            replay = nil
            return
        }
        replay = Replay.make(spans[chosen], from: source)
    }

    // MARK: Chips

    private var chips: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(Array(spans.enumerated()), id: \.offset) { index, span in
                        let isChosen = index == chosen
                        Text(verbatim: span.chipTitle())
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            // `accentFill` under `onAccent`, never `accent`
                            // under a hardcoded black: the chosen chip has to
                            // stay readable on every palette.
                            .background(isChosen ? LSTheme.accentFill : LSTheme.cardFill, in: .capsule)
                            .foregroundStyle(isChosen ? LSTheme.onAccent : .secondary)
                            .contentShape(.capsule)
                            .onTapGesture { chosen = index }
                            .id(index)
                            .accessibilityAddTraits(isChosen ? [.isButton, .isSelected] : .isButton)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
            }
            .scrollIndicators(.hidden)
            // Fades at the right edge so the row reads as one that scrolls.
            .mask(LinearGradient(stops: [.init(color: .black, location: 0.84),
                                         .init(color: .clear, location: 1)],
                                 startPoint: .leading, endPoint: .trailing))
            // The chosen chip stays in view — it used to scroll off, leaving
            // only the bar to say which span you were reading (Fable, 09-21).
            .onChange(of: chosen) { _, index in
                withAnimation { proxy.scrollTo(index, anchor: .center) }
            }
        }
        // Its own backing, outside the fade: the bar's glass stopped at the
        // bar, and the page scrolled visibly under the chips — "What you
        // played" ran straight through "September".
        .background(.bar)
    }

    // MARK: Save as image

    @ViewBuilder
    private var saveButton: some View {
        if let replay {
            Button {
                Task { await export(replay) }
            } label: {
                HStack(spacing: 8) {
                    if exporting { ProgressView().controlSize(.small) }
                    Label("Save as image", systemImage: "square.and.arrow.down")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(LSTheme.accent)
                .frame(maxWidth: .infinity)
                .padding(13)
                .background(LSTheme.cardFill, in: .rect(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .disabled(exporting)
        }
    }

    /// **The page, without the chips or Done, as one image.**
    ///
    /// `ImageRenderer` draws synchronously, and covers load through
    /// `AsyncImage` — so rendering the live page would leave a gray box
    /// wherever a cover goes. The covers it needs are loaded first and handed
    /// in, and the page draws those instead.
    @MainActor
    private func export(_ replay: Replay) async {
        exporting = true
        defer { exporting = false }
        let covers = await ReplayCovers.load(Self.coverIDs(for: replay), from: games)
        let page = ReplayShareCard(replay: replay, games: games)
            .environment(\.replayCovers, covers)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: page)
        renderer.scale = 3
        guard let data = Self.png(from: renderer) else { return }
        let name = "Replay \(replay.span.title()).png".replacingOccurrences(of: "/", with: "-")
        let url = URL.temporaryDirectory.appending(path: name)
        do {
            try data.write(to: url, options: .atomic)
            #if canImport(UIKit)
            guard let image = renderer.uiImage else { return }
            exportURL = ExportedImage(url: url, image: image)
            #else
            exportURL = ExportedImage(url: url)
            #endif
        } catch {}
    }

    private static func png(from renderer: ImageRenderer<some View>) -> Data? {
        #if canImport(UIKit)
        renderer.uiImage?.pngData()
        #else
        renderer.nsImage?.tiffRepresentation
            .flatMap(NSBitmapImageRep.init(data:))?
            .representation(using: .png, properties: [:])
        #endif
    }

    /// Every cover the page can draw, so the export has them all in hand.
    static func coverIDs(for replay: Replay) -> [UUID] {
        var ids = replay.played.prefix(5).map(\.id)
        ids += replay.finished.map(\.id)
        ids += replay.carried.compactMap(\.gameID)
        var seen = Set<UUID>()
        return ids.filter { seen.insert($0).inserted }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nothing to replay yet")
                .font(.title3.weight(.semibold))
            Text("Time a session, finish something, or write a memory, and this fills in on its own.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(LSTheme.cardFill, in: .rect(cornerRadius: 18))
    }
}

// MARK: - The page

/// The part of a Replay that is the Replay — what Save as image draws.
private struct ReplayPage: View {
    let replay: Replay
    let games: [UUID: Game]
    /// Drawn for Save as image: nothing on it can be tapped, so nothing on
    /// it says to.
    var forExport = false
    var openBadges: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            hero
            VStack(alignment: .leading, spacing: 6) {
                Text(replay.sentence)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if let facts {
                    Text(verbatim: facts)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !replay.played.isEmpty { played }
            if showsFinishPanel { finishes }
            if !replay.carried.isEmpty { carried }
            if !replay.badges.isEmpty { badges }
            aside
        }
    }

    // MARK: Hero

    /// Which story the top of the page tells.
    private enum Hero {
        case cover(UUID, total: String?)
        case mosaic([UUID], more: Int, total: String, caption: String?)
        case figure(String, caption: String)
    }

    private var heroKind: Hero? {
        switch replay.lead {
        case .timed(let seconds):
            let total = Format.duration(seconds)
            // One game, or one game with most of it: its cover is the story.
            if let top = replay.played.first,
               replay.played.count == 1 || top.seconds / replay.totalSeconds >= 0.6 {
                return .cover(top.id, total: total)
            }
            let ids = replay.played.map(\.id)
            return .mosaic(Array(ids.prefix(5)), more: max(0, ids.count - 5), total: total, caption: nil)
        case .placed(let seconds):
            var seen = Set<UUID>()
            let ids = replay.carried.compactMap(\.gameID).filter { seen.insert($0).inserted }
            let caption = "from before you tracked"
            if ids.count == 1 { return .mosaic(ids, more: 0, total: Format.duration(seconds), caption: caption) }
            return .mosaic(Array(ids.prefix(5)), more: max(0, ids.count - 5),
                           total: Format.duration(seconds), caption: caption)
        case .finished:
            // No hero zero: a period with no play gets its finish, not a total.
            if replay.finished.count == 1 { return .cover(replay.finished[0].id, total: nil) }
            return .mosaic(Array(replay.finished.map(\.id).prefix(5)),
                           more: max(0, replay.finished.count - 5),
                           total: String(replay.finished.count), caption: "games finished")
        case .added(let n):
            return .figure(String(n), caption: n == 1 ? "game joined your library" : "games joined your library")
        case .remembered(let n):
            return .figure(String(n), caption: n == 1 ? "memory written" : "memories written")
        case .none:
            return nil
        }
    }

    @ViewBuilder
    private var hero: some View {
        switch heroKind {
        case .cover(let id, let total):
            ZStack(alignment: .bottomLeading) {
                ReplayCover(id: id, game: games[id])
                    .frame(maxWidth: .infinity)
                    .frame(height: 230)
                    .clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.75)],
                               startPoint: .center, endPoint: .bottom)
                if let total {
                    Text(verbatim: total)
                        .font(LSTheme.pixel(40))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .padding(14)
                }
            }
            .frame(height: 230)
            .clipShape(.rect(cornerRadius: 18))
            .accessibilityElement(children: .combine)
        case .mosaic(let ids, let more, let total, let caption):
            VStack(alignment: .leading, spacing: 10) {
                Mosaic(ids: ids, more: more, games: games)
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: total)
                        .font(LSTheme.pixel(36))
                        .foregroundStyle(LSTheme.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    if let caption {
                        Text(caption).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        case .figure(let number, let caption):
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: number)
                    .font(LSTheme.pixel(40))
                    .foregroundStyle(LSTheme.accent)
                Text(caption).font(.footnote).foregroundStyle(.secondary)
            }
        case .none:
            EmptyView()
        }
    }

    /// One quiet line under the sentence.
    private var facts: String? {
        if replay.sessionCount > 0 {
            let days = replay.daysPlayed == 1 ? "1 day" : "\(replay.daysPlayed) days"
            let gamesText = replay.gamesPlayedCount == 1 ? "1 game" : "\(replay.gamesPlayedCount) games"
            let sessions = replay.sessionCount == 1 ? "1 session" : "\(replay.sessionCount) sessions"
            return "\(days) · \(gamesText) · \(sessions)"
        }
        // A finish and no play: when, as exactly as it was recorded, and on
        // what — "Sometime in 2015 · SNES", never "Jan 1".
        if replay.finished.count == 1, let finish = replay.finished.first {
            let when = finish.dateText.count == 4 ? "Sometime in \(finish.dateText)" : finish.dateText
            return [when, finish.platform.map(PlatformShort.name)].compactMap { $0 }.joined(separator: " · ")
        }
        return nil
    }

    // MARK: Panels

    private var played: some View {
        panel("What you played") {
            let top = Array(replay.played.prefix(5))
            let most = top.first?.seconds ?? 1
            VStack(spacing: 10) {
                ForEach(top) { game in
                    HStack(spacing: 10) {
                        ReplayCover(id: game.id, game: games[game.id])
                            .frame(width: 34, height: 46)
                            .clipShape(.rect(cornerRadius: 5))
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(game.name)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text(verbatim: Format.duration(game.seconds))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            // Against the period's own leader, so the shape is
                            // of this period rather than of the library.
                            GeometryReader { proxy in
                                Capsule()
                                    .fill(LSTheme.accentFill)
                                    .frame(width: max(3, proxy.size.width * (game.seconds / most)))
                            }
                            .frame(height: 6)
                        }
                    }
                }
            }
        }
    }

    /// The finish panel, unless the one finish is already the hero.
    private var showsFinishPanel: Bool {
        !replay.finished.isEmpty && !(replay.sessionCount == 0 && replay.finished.count == 1)
    }

    private var finishes: some View {
        panel(replay.finished.count == 1 ? "What you finished"
                                         : "What you finished — \(replay.finished.count)") {
            VStack(spacing: 8) {
                ForEach(replay.finished) { finish in
                    HStack(spacing: 10) {
                        ReplayCover(id: finish.id, game: games[finish.id])
                            .frame(width: 26, height: 35)
                            .clipShape(.rect(cornerRadius: 4))
                        Text(finish.name)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(verbatim: finish.dateText)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// Hours from before tracking. On a year's page they are the ones placed
    /// in that year; on "Before you tracked" they are all of them.
    private var carried: some View {
        let isBefore = replay.span == .beforeTracking
        return panel(isBefore ? "From before you tracked" : "Also this year, from before you tracked") {
            VStack(spacing: 8) {
                ForEach(replay.carried) { line in
                    HStack(spacing: 10) {
                        if let id = line.gameID {
                            ReplayCover(id: id, game: games[id])
                                .frame(width: 26, height: 35)
                                .clipShape(.rect(cornerRadius: 4))
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(line.name)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            // Its years, where they were given. A range names
                            // itself on every year it touches, so nobody reads
                            // it as this year's alone.
                            if isBefore || line.isRange {
                                Text(verbatim: line.span.isEmpty ? "no years given"
                                     : (line.isRange ? "across \(line.span)" : line.span))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 8)
                        Text(verbatim: Format.duration(line.seconds))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Text(isBefore
                     ? "What your storefronts reported, with the years you placed it in. None of it is in a year's play, because it has no days in it."
                     : "Hours you placed here. They aren't in the play above, because they have no days in them.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
    }

    /// **One row, top-aligned, never growing.** Three badges and a "+N" that
    /// opens the lens, so nothing sits lower than its neighbors and the page
    /// doesn't lengthen with every badge earned (Fable's mockup).
    private var badges: some View {
        let all = replay.badges
        let shown = all.count > 4 ? Array(all.prefix(3)) : all
        return panel(all.count == 1 ? "A badge this \(replay.periodWord)"
                                    : "\(all.count) badges this \(replay.periodWord)") {
            HStack(alignment: .top, spacing: 6) {
                ForEach(shown) { badge in
                    VStack(spacing: 5) {
                        BadgeArt(badge: badge, size: 48)
                        Text(badge.title)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity)
                }
                if all.count > 4 {
                    Button(action: openBadges) {
                        VStack(spacing: 5) {
                            Text(verbatim: "+\(all.count - 3)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 48, height: 48)
                                .background(Circle().fill(LSTheme.cardFill))
                            Text(forExport ? "more" : "See all")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// The quieter facts. The longest day and the longest sitting are one
    /// line when they were the same thing — they used to be two lines that
    /// both said 3h 25m.
    @ViewBuilder
    private var aside: some View {
        let lines = asideLines
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(lines, id: \.self) { line in
                    Text(verbatim: line)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var asideLines: [String] {
        var out: [String] = []
        if let busiest = replay.busiestDay, replay.sessionCount > 1 {
            let day = busiest.day.formatted(.dateTime.month(.wide).day())
            if abs(busiest.seconds - replay.longestSession) < 60 {
                out.append("Your longest sitting was \(Format.duration(replay.longestSession)), on \(day).")
            } else {
                out.append("Your longest day was \(day), at \(Format.duration(busiest.seconds)); your longest sitting, \(Format.duration(replay.longestSession)).")
            }
        }
        if replay.added > 0, replay.lead != .added(replay.added) {
            out.append(replay.added == 1 ? "A game joined the library." : "\(replay.added) games joined the library.")
        }
        if replay.memoriesWritten > 0, replay.lead != .remembered(replay.memoriesWritten) {
            out.append(replay.memoriesWritten == 1 ? "You wrote a memory." : "You wrote \(replay.memoriesWritten) memories.")
        }
        return out
    }

    private func panel<Content: View>(_ title: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(LSTheme.cardFill, in: .rect(cornerRadius: 16))
    }
}

// MARK: - The share card

/// **What Save as image makes: a card for posting, not a copy of the page.**
///
/// The first export drew the page itself. It carried none of LevelSelect:
/// no wordmark, no pixel face, no console. Its words ("The year you finished
/// Kirby and the Forgotten Land", then "Made on this device, from your own
/// records. Nothing left it.") read as a report about the export rather than
/// something anyone would post. Tim, 09-21: *"Nothing about this says
/// LevelSelect either. No branding, no typeface, color, console icon,
/// nothing."*
///
/// So it's a poster, 4:5 so it fills a feed: the wordmark and the period in
/// the pixel face, the art, one short headline, the console, and where the
/// app lives. The page keeps the detail; the card keeps the one thing worth
/// saying.
private struct ReplayShareCard: View {
    let replay: Replay
    let games: [UUID: Game]

    static let size = CGSize(width: 360, height: 450)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Wordmark(size: 12, showsIcon: true)
                    .fixedSize()
                    .layoutPriority(1)
                Spacer(minLength: 8)
                Text(verbatim: "REPLAY · \(replay.span.title().uppercased())")
                    .font(LSTheme.pixel(8))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.bottom, 14)

            art
                .frame(height: 250)
                .clipShape(.rect(cornerRadius: 16))

            Text(verbatim: label)
                .font(LSTheme.pixel(10))
                .foregroundStyle(LSTheme.torch)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.top, 16)
            Text(verbatim: headline)
                .font(.system(size: 23, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 7)
            detailRow
                .padding(.top, 9)

            Spacer(minLength: 0)
            Text(verbatim: "levelselect.app")
                .font(LSTheme.pixel(7))
                .foregroundStyle(.white.opacity(0.45))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(20)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(LSTheme.ground(lightTint: ThemePalette.backgroundOverrideLight,
                                   darkTint: ThemePalette.backgroundOverrideDark))
    }

    // MARK: What it says

    /// The one finish, when a finish is the whole story.
    private var soleFinish: Replay.Finish? {
        replay.sessionCount == 0 && replay.finished.count == 1 ? replay.finished.first : nil
    }

    /// The pixel line over the headline. A finish uses the word you gave it
    /// ("BEATEN", "100%"), not one of the app's.
    private var label: String {
        if let finish = soleFinish {
            return finish.label.isEmpty ? "FINISHED" : finish.label.uppercased()
        }
        switch replay.lead {
        case .timed(let seconds): return "\(Format.duration(seconds).uppercased()) PLAYED"
        case .finished: return "\(replay.finished.count) FINISHED"
        case .placed(let seconds): return "\(Format.duration(seconds).uppercased()) BEFORE TRACKING"
        case .added(let n): return n == 1 ? "1 GAME ADDED" : "\(n) GAMES ADDED"
        case .remembered(let n): return n == 1 ? "1 MEMORY" : "\(n) MEMORIES"
        case .none: return "REPLAY"
        }
    }

    /// The game's name when one game is the story; the page's sentence
    /// otherwise.
    private var headline: String {
        if let finish = soleFinish { return finish.name }
        return replay.sentence
    }

    /// The console, with its icon, and the date when it says more than the
    /// period already does.
    @ViewBuilder
    private var detailRow: some View {
        let platform = self.platform
        let when: String? = {
            guard let finish = soleFinish, finish.dateText != replay.span.title() else { return nil }
            return finish.dateText
        }()
        let stats: String? = replay.sessionCount > 0
            ? [replay.daysPlayed == 1 ? "1 day" : "\(replay.daysPlayed) days",
               replay.gamesPlayedCount == 1 ? "1 game" : "\(replay.gamesPlayedCount) games"]
                .joined(separator: " · ")
            : nil
        let words = [platform.map(PlatformShort.name), when, stats].compactMap { $0 }
        if !words.isEmpty {
            HStack(spacing: 8) {
                if let platform {
                    PlatformIconView(platform: platform, size: 26)
                        .frame(width: 30, height: 26)
                }
                Text(verbatim: words.joined(separator: " · "))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    /// The console the story happened on: the finish's, else the lead game's.
    private var platform: String? {
        if let finish = soleFinish {
            return finish.platform ?? games[finish.id].flatMap { $0.chosenPlatform ?? $0.platforms.first }
        }
        guard let id = leadIDs.first, let game = games[id] else { return nil }
        return game.chosenPlatform ?? game.platforms.first
    }

    // MARK: The art

    private var leadIDs: [UUID] {
        switch replay.lead {
        case .timed:
            if let top = replay.played.first,
               replay.played.count == 1 || top.seconds / max(replay.totalSeconds, 1) >= 0.6 {
                return [top.id]
            }
            return replay.played.map(\.id)
        case .finished:
            return replay.finished.map(\.id)
        case .placed:
            var seen = Set<UUID>()
            return replay.carried.compactMap(\.gameID).filter { seen.insert($0).inserted }
        default:
            return replay.played.map(\.id) + replay.finished.map(\.id)
        }
    }

    @ViewBuilder
    private var art: some View {
        let ids = leadIDs
        if ids.count == 1, let id = ids.first {
            // **The whole box, not a strip of it.** A portrait cover cut to
            // a wide band kept its middle third; here it stands at full
            // height over a blurred wash of its own colors.
            ZStack {
                ReplayCover(id: id, game: games[id])
                    .frame(width: Self.size.width - 40, height: 250)
                    .blur(radius: 24, opaque: true)
                    .overlay(Color.black.opacity(0.25))
                    .clipped()
                ReplayCover(id: id, game: games[id])
                    .frame(width: 168, height: 224)
                    .clipShape(.rect(cornerRadius: 8))
                    .shadow(color: .black.opacity(0.5), radius: 14, y: 8)
            }
        } else if !ids.isEmpty {
            Mosaic(ids: Array(ids.prefix(5)), more: max(0, ids.count - 5), games: games)
        } else {
            // Nothing with a cover: the period itself, large.
            Text(verbatim: replay.span.title())
                .font(LSTheme.pixel(34))
                .foregroundStyle(LSTheme.torch)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.white.opacity(0.06))
        }
    }
}

// MARK: - Covers

/// The leaders' covers, the first one large.
///
/// Up to five: one tall on the left, up to four on the right, and "+N more"
/// in the last place when there were more. Fable's mockup sized tiles by
/// share of hours and was least sure of it — eleven near-equal games could
/// make an ugly mosaic — so this is the fixed version it named as safe.
private struct Mosaic: View {
    let ids: [UUID]
    let more: Int
    let games: [UUID: Game]

    private let height: CGFloat = 227
    private let gap: CGFloat = 3

    /// A place in the right-hand grid: a game, or the "+N more" tile.
    private struct Slot: Hashable { let id: UUID? }

    var body: some View {
        // **Every tile framed explicitly.** Left to the stacks, each cover
        // asserted its own aspect ratio against the space it was offered, and
        // the right-hand tiles came out uneven — "+6 more" shorter than the
        // Hades beside it. Measured once, then placed.
        GeometryReader { proxy in
            let slots = rightSlots
            let leadWidth = slots.isEmpty ? proxy.size.width : (proxy.size.width - gap) / 2
            let rightWidth = proxy.size.width - leadWidth - gap
            let rows = stride(from: 0, to: slots.count, by: 2).map {
                Array(slots[$0..<min($0 + 2, slots.count)])
            }
            let rowHeight = rows.isEmpty ? height
                : (height - gap * CGFloat(rows.count - 1)) / CGFloat(rows.count)
            HStack(spacing: gap) {
                if let lead = ids.first {
                    tile(lead, width: leadWidth, height: height)
                }
                if !rows.isEmpty {
                    VStack(spacing: gap) {
                        ForEach(rows, id: \.self) { row in
                            let tileWidth = (rightWidth - gap * CGFloat(row.count - 1)) / CGFloat(row.count)
                            HStack(spacing: gap) {
                                ForEach(row, id: \.self) { slot in
                                    if let id = slot.id {
                                        tile(id, width: tileWidth, height: rowHeight)
                                    } else {
                                        moreTile.frame(width: tileWidth, height: rowHeight)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(height: height)
        .clipShape(.rect(cornerRadius: 18))
    }

    /// Up to four beside the lead, the "+N more" tile taking the last place.
    private var rightSlots: [Slot] {
        var slots = ids.dropFirst().prefix(more > 0 ? 3 : 4).map { Slot(id: $0) }
        if more > 0 { slots.append(Slot(id: nil)) }
        return slots
    }

    /// Clipped at its exact size. A flexible frame takes the size of an
    /// oversized child, so clipping there let a cover spill over the tile
    /// below it; the size has to be the one the grid measured.
    private func tile(_ id: UUID, width: CGFloat, height: CGFloat) -> some View {
        ReplayCover(id: id, game: games[id])
            .frame(width: width, height: height)
            .clipped()
            .overlay(alignment: .bottomLeading) {
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(colors: [.clear, .black.opacity(0.7)],
                                   startPoint: .center, endPoint: .bottom)
                    Text(games[id]?.name ?? "")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .padding(8)
                }
            }
    }

    private var moreTile: some View {
        Text(verbatim: "+\(more) more")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LSTheme.cardFill)
    }
}

/// A game's cover — the preloaded one when the page is being saved as an
/// image, the live one otherwise.
private struct ReplayCover: View {
    let id: UUID
    let game: Game?
    @Environment(\.replayCovers) private var covers

    var body: some View {
        if let image = covers[id] {
            image.resizable().aspectRatio(contentMode: .fill)
        } else if let game {
            CoverThumb(urlString: game.displayCoverURLString,
                       artwork: game.resolvedArtwork(.cover),
                       name: game.name, status: game.status)
        } else {
            LSTheme.cardFill
        }
    }
}

/// Covers loaded ahead of `ImageRenderer`, which can't wait for `AsyncImage`.
/// On the main actor because it reads `Game` models; the downloads still
/// suspend rather than block.
@MainActor
enum ReplayCovers {
    /// IGDB serves every size from one id; swap the size segment.
    static func sharp(_ url: URL) -> URL {
        let text = url.absoluteString
        guard text.contains("images.igdb.com") else { return url }
        for size in ["/t_cover_big/", "/t_cover_small/", "/t_thumb/", "/t_720p/"]
        where text.contains(size) {
            return URL(string: text.replacingOccurrences(of: size, with: "/t_1080p/")) ?? url
        }
        return url
    }

    static func load(_ ids: [UUID], from games: [UUID: Game]) async -> [UUID: Image] {
        var out: [UUID: Image] = [:]
        for id in ids {
            guard let game = games[id] else { continue }
            var data: Data?
            switch game.resolvedArtwork(.cover) {
            case .local(let bytes): data = bytes
            // The large size for a picture people will post: the library's
            // `t_cover_big` is 264 wide and went soft at 1080.
            case .remote(let url): data = try? await URLSession.shared.data(from: sharp(url)).0
            case .none: break
            }
            #if canImport(UIKit)
            if let data, let image = UIImage(data: data) { out[id] = Image(uiImage: image) }
            #else
            if let data, let image = NSImage(data: data) { out[id] = Image(nsImage: image) }
            #endif
        }
        return out
    }
}

private struct ReplayCoversKey: EnvironmentKey {
    static let defaultValue: [UUID: Image] = [:]
}

extension EnvironmentValues {
    var replayCovers: [UUID: Image] {
        get { self[ReplayCoversKey.self] }
        set { self[ReplayCoversKey.self] = newValue }
    }
}

// MARK: - The door

/// The door into a Replay, at the top of the Charts lens.
///
/// It names the period and says its one sentence, so opening it is a choice
/// rather than a gamble — and it says nothing at all when there is nothing to
/// say, rather than offering a recap of a month you didn't play.
struct ReplayEntryCard: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var replay: Replay?
    @State private var showing = false

    var body: some View {
        Group {
            if let replay {
                card(replay)
            } else {
                // **A sliver, not nothing.** This card sits in a `LazyVStack`,
                // which never realizes a child that lays out to zero — so a
                // plain `EmptyView` here meant the `.task` below never ran and
                // the card never appeared at all (09-21).
                Color.clear.frame(height: 1)
            }
        }
        .task {
            let spans = ReplayBuilder.availableSpans(in: context)
            guard let first = spans.first else { return }
            replay = Replay.make(first, from: ReplayBuilder.source(in: context))
        }
        .sheet(isPresented: $showing) { ReplayView().lsSheet([.large]) }
    }

    private func card(_ replay: Replay) -> some View {
        HStack(spacing: 14) {
            // Decoration, so it steps aside at the largest sizes: beside it,
            // "September 2026" had room only to hyphenate (Fable, 09-21).
            if !typeSize.isAccessibilitySize {
                ZStack {
                    Circle().fill(LSTheme.accent.opacity(0.16)).frame(width: 46, height: 46)
                    Image(systemName: "sparkles")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(LSTheme.accent)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "Replay · \(replay.span.chipTitle())")
                    .font(.headline)
                Text(replay.sentence)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 6)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(LSTheme.cardFill, in: .rect(cornerRadius: 16))
        .contentShape(.rect)
        .onTapGesture { showing = true }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Replay: \(replay.span.title()). \(replay.sentence)")
        .accessibilityAddTraits(.isButton)
    }
}

#if canImport(UIKit)
/// The share sheet for a picture rather than a file, so "Save Image" is
/// offered and a Replay lands in Photos (which needs only the add-only
/// permission — see `NSPhotoLibraryAddUsageDescription`).
private struct ImageShareSheet: UIViewControllerRepresentable {
    let image: UIImage
    var title = "Replay"
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [Preview(image: image, title: title)],
                                 applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}

    /// **The card in the sheet's header.** Handed over bare, the image
    /// showed as a blank placeholder tile, so you couldn't see what you were
    /// about to post (09-21). Link metadata is what the header draws.
    final class Preview: NSObject, UIActivityItemSource {
        let image: UIImage
        let title: String
        init(image: UIImage, title: String) { self.image = image; self.title = title }

        func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any { image }
        func activityViewController(_ controller: UIActivityViewController,
                                    itemForActivityType activityType: UIActivity.ActivityType?) -> Any? { image }
        func activityViewControllerLinkMetadata(_ controller: UIActivityViewController) -> LPLinkMetadata? {
            let metadata = LPLinkMetadata()
            metadata.title = title
            let provider = NSItemProvider(object: image)
            metadata.imageProvider = provider
            metadata.iconProvider = provider
            return metadata
        }
    }
}
#endif
