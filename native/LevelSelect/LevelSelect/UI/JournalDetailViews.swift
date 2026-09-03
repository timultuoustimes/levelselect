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
                            HStack(spacing: 8) {
                                Image(systemName: "dice.fill").foregroundStyle(.secondary)
                                Text(run.outcome.journalText)
                                Spacer()
                                Text((run.endedAt ?? run.startedAt)
                                    .formatted(date: .omitted, time: .shortened))
                                    .foregroundStyle(.tertiary)
                            }
                            .font(.subheadline)
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
                CoverThumb(urlString: game.displayCoverURLString)
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
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "timer").foregroundStyle(.secondary)
                Text(Format.duration(session.elapsed()))
                Spacer()
                Text(session.startDate.formatted(date: .omitted, time: .shortened))
                    .foregroundStyle(.tertiary)
            }
            .font(.subheadline)
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
            Text(title).font(.headline)
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
            VStack(alignment: .leading, spacing: 16) {
                gallery

                VStack(alignment: .leading, spacing: 8) {
                    Text(memory.title).font(.title2.weight(.semibold))
                    // Always the user's words for the date — never re-rendered
                    // from the interval. See Memory.dateText.
                    Text(memory.dateText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let detail = memory.detailLine {
                        Label(detail, systemImage: "sparkles")
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

                if let game = memory.game {
                    NavigationLink(value: game) {
                        HStack(spacing: 10) {
                            CoverThumb(urlString: game.displayCoverURLString)
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
        .sheet(isPresented: $editing) { MemorySheet(existing: memory) }
        .sheet(item: $viewingImage) { LocalImageViewer(image: $0) }
    }
}
