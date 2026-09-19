import SwiftUI
import SwiftData

/// Everything one game saw on one day.
///
/// The timeline says *"Mina the Hollower · 47m · 3 sessions"*; this is what
/// those three sessions were. Tim: *"you can tap on each game and it gives a
/// full breakdown of what you did in that game and tells you each session that
/// you had, what you journaled about each session, if you beat the game in the
/// last session."*
///
/// Reading, not editing — the row's long-press does that. Conflating the two
/// is what made the old row open an editor when all anyone wanted was to see
/// what they had written.
struct JournalDayView: View {
    let entry: JournalEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if !entry.finishes.isEmpty {
                    ForEach(entry.finishes) { finish in
                        finishRow(finish)
                    }
                }

                if !entry.sessions.isEmpty {
                    section("Sessions") {
                        ForEach(entry.sessions) { session in
                            sessionRow(session)
                        }
                    }
                }

                if !entry.runs.isEmpty {
                    section("Runs") {
                        ForEach(entry.runs) { run in
                            let at = (run.endedAt ?? run.startedAt)
                                .formatted(date: .omitted, time: .shortened)
                            HStack(spacing: 8) {
                                Image(systemName: "dice.fill")
                                    .foregroundStyle(.secondary)
                                    // The glyph repeats the word beside it.
                                    .accessibilityHidden(true)
                                Text(run.outcome.journalText)
                                Spacer()
                                Text(at).foregroundStyle(.tertiary)
                            }
                            .font(.subheadline)
                            // One element, one sentence. Swiping through three
                            // fragments — a glyph, "Run lost", "8:22 PM" — is
                            // how a row that IS on screen reads as if it were
                            // not there.
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(run.outcome.journalText), \(at)")
                            if let note = run.notes?.journalText {
                                Text(note).font(.callout).padding(.bottom, 4)
                            }
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .lsBackground()
        .navigationTitle(entry.title)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    /// The header is a link to the game.
    ///
    /// This view reads; the game page is where things are changed. Tim: *"when
    /// you tap the game it opens the game's page… that way they can view the
    /// game info and make edits to sessions and stuff from there."* Rather
    /// than growing an editor here, the read view points at the one that
    /// already exists — and the game page already owns session editing,
    /// artwork, trackers and everything else.
    @ViewBuilder
    private var header: some View {
        if let game = entry.game {
            NavigationLink(value: game) { headerContent(game) }
                .buttonStyle(.plain)
        } else {
            headerContent(nil)
        }
    }

    private func headerContent(_ game: Game?) -> some View {
        HStack(alignment: .top, spacing: 14) {
            if let game {
                CoverThumb(urlString: game.displayCoverURLString,
                           artwork: game.resolvedArtwork(.cover), name: game.name, status: game.status)
                    .frame(width: 74, height: 99)
                    .clipShape(.rect(cornerRadius: 8))
                    .coverGloss()
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.title).font(.title3.weight(.semibold))
                Text(entry.date.formatted(date: .complete, time: .omitted))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if entry.duration > 0 {
                    Text("\(Format.duration(entry.duration)) · \(entry.sessions.count) "
                         + (entry.sessions.count == 1 ? "session" : "sessions"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if game != nil {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .lsCard()
    }

    private func finishRow(_ finish: CompletionEvent) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(finish.journalLabel, systemImage: "flag.checkered")
                .font(.headline)
            // Which session it landed in is the thing worth saying: "beaten in
            // the last one" is a different evening from "beaten first thing".
            if let last = entry.sessions.last, finish.date >= last.startDate,
               entry.sessions.count > 1 {
                Text("In the last session of the day.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let note = finish.notes?.journalText {
                Text(note).font(.callout)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lsCard()
    }

    private func sessionRow(_ session: Session) -> some View {
        let started = session.startDate.formatted(date: .omitted, time: .shortened)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "timer")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(Format.duration(session.elapsed()))
                Spacer()
                Text(started).foregroundStyle(.tertiary)
            }
            .font(.subheadline)
            // "17m 25s, started 9:15 PM" rather than a duration and a time
            // arriving as two unrelated announcements.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(Format.duration(session.elapsed())), started \(started)")
            if let note = session.notes?.journalText {
                Text(note).font(.callout)
            }
            if !session.companions.isEmpty {
                Label(session.companions.map(\.name).joined(separator: ", "),
                      systemImage: "person.2.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // A heading, so rotor navigation can reach "Sessions" and "Runs"
            // instead of only finding their contents by swiping past
            // everything above them.
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lsCard()
    }
}

/// A memory, read rather than edited.
///
/// The shape is the game page's: a big image, then the words. One picture
/// becomes the header; several become a mosaic — **the count decides the
/// layout, so nobody has to nominate a key photo.** That is the whole reason
/// no `keyPhoto` field exists.
struct MemoryView: View {
    let memory: Memory
    @State private var editing = false
    @State private var viewingImage: GameImage?

    private var images: [GameImage] {
        (memory.images ?? []).filter { $0.deletedAt == nil }
            .sorted { $0.addedAt < $1.addedAt }
    }

    /// One big, the rest two-up beneath it.
    ///
    /// **The first picture is always the hero.** An adaptive grid gave every
    /// photo the same small cell, which made three screenshots read as a
    /// contact sheet rather than a memory — Tim: *"it needs to be a hero one
    /// up, 2 up below."* One rule covers every count: at one you get the hero
    /// alone, at three exactly what he described, and at five it keeps going
    /// in pairs rather than inventing a second layout.
    @ViewBuilder
    private var gallery: some View {
        if let first = images.first {
            VStack(spacing: 8) {
                if let data = first.data {
                    Button { viewingImage = first } label: {
                        photo(data, height: 240, radius: 14)
                    }
                    .buttonStyle(.plain)
                }
                let rest = Array(images.dropFirst())
                if !rest.isEmpty {
                    LazyVGrid(columns: Self.pair, spacing: 8) {
                        ForEach(rest) { image in
                            if let data = image.data {
                                Button { viewingImage = image } label: {
                                    // Shorter than the hero, and wider than the
                                    // old cells were — half the content width
                                    // rather than a third, so a screenshot is
                                    // still legible at a glance.
                                    photo(data, height: 140, radius: 12)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    private static let pair = [GridItem(.flexible(), spacing: 8),
                               GridItem(.flexible(), spacing: 8)]

    /// A picture at a fixed height, cut to its cell.
    ///
    /// **The size comes from a shape, and the clip is outermost.** Setting
    /// `.frame(height:)` on the image constrains one axis only: a 16:9
    /// screenshot 108 tall is 192 wide, which overflows a 118pt grid column,
    /// and `clipShape` then rounds the *overflowing* rectangle rather than the
    /// cell — so three photos bled to the screen edges with no gaps and no
    /// corners. `DayCell` had the same bug for the same reason; a shape takes
    /// the cell's width, the image rides as an overlay, and one clip at the
    /// end cuts whatever escaped.
    private func photo(_ data: Data, height: CGFloat, radius: CGFloat) -> some View {
        Rectangle()
            .fill(LSTheme.cardFill)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay { LocalArtworkThumb(data: data, contentMode: .fill) }
            .clipShape(.rect(cornerRadius: radius))
    }

    var body: some View {
        ScrollView {
            // **Words before pictures.** This opened on the gallery, so a
            // memory with three photos pushed its own title, its date and
            // everything you wrote below the fold — Fable's 3.3: *"A Memory
            // opens on pictures and hides the words and the date."* The
            // pictures are the illustration; the sentence you wrote down is
            // the entry. The gallery keeps its hero-then-grid shape exactly,
            // it just sits under the text now.
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(memory.title).font(.title2.weight(.semibold))
                    // Always the user's words for the date — never re-rendered
                    // from the interval. See Memory.dateText.
                    Text(memory.dateText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let detail = memory.detailLine {
                        // `tag`, not the memory glyph: this line is the
                        // entry's labels — kind, console, place — not the
                        // entry itself, and the mark beside a heading should
                        // not be the same one that marks the whole thing.
                        Label(detail, systemImage: "tag")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if !memory.companions.isEmpty {
                        Label(memory.companions.map(\.name).joined(separator: ", "),
                              systemImage: "person.2.fill")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if let body = memory.body?.journalText {
                    Text(body)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                gallery

                if let game = memory.game {
                    NavigationLink(value: game) {
                        HStack(spacing: 10) {
                            CoverThumb(urlString: game.displayCoverURLString,
                           artwork: game.resolvedArtwork(.cover), name: game.name, status: game.status)
                                .frame(width: 36, height: 48)
                                .clipShape(.rect(cornerRadius: 5))
                            Text(game.name).font(.subheadline.weight(.medium))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .lsCard()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .lsBackground()
        .navigationTitle("Memory")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            Button { editing = true } label: { Label("Edit", systemImage: "square.and.pencil") }
        }
        .sheet(isPresented: $editing) { MemorySheet(existing: memory).lsSheet() }
        .sheet(item: $viewingImage) { LocalImageViewer(image: $0) }
    }
}
