import Foundation
import SwiftData

/// A question the app has for you about a console, raised by a game.
///
/// **Why the app asks instead of inferring.** A physical game does not imply a
/// physical console: people buy sealed copies, display copies, and cartridges
/// for hardware they have never owned. Marking the console owned because a
/// game is would quietly put a machine in someone's display case that they do
/// not have. So the game raises a question and the person answers it —
/// once, and the answer is remembered either way.
struct ConsoleQuestion: Identifiable, Hashable, Sendable {
    /// The canonical platform name, as `PlatformKey.canonical` folds it.
    let platform: String
    /// The ownership the games have and the console does not.
    let ownership: Ownership
    /// How many of your games on that console say so. One is a display copy;
    /// eleven is a machine.
    let games: Int

    var id: String { "\(platform)|\(ownership.rawValue)" }
}

extension Repository {

    // MARK: Reading

    /// Every console you own, newest tombstones excluded.
    func liveConsoles() -> [Console] {
        let d = FetchDescriptor<Console>(predicate: #Predicate { $0.deletedAt == nil })
        return ((try? context.fetch(d)) ?? []).sorted { $0.platform < $1.platform }
    }

    /// The console for a platform under ANY of its spellings.
    func console(forPlatform raw: String) -> Console? {
        let key = PlatformKey.canonical(raw)
        return liveConsoles().first { $0.platform == key }
    }

    func trashedConsoles() -> [Console] {
        let d = FetchDescriptor<Console>(predicate: #Predicate { $0.deletedAt != nil })
        return ((try? context.fetch(d)) ?? []).sorted {
            ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast)
        }
    }

    /// Platforms you have said you do not want a console for. See
    /// `ThemeSettings.dismissedConsolesRaw`.
    func dismissedConsoles() -> Set<String> {
        let raw = themeRow()?.dismissedConsolesRaw ?? ""
        return Set(raw.split(separator: ",").map {
            String($0).trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty })
    }

    /// The one settings row, without reaching into `UI` — `ThemePalette` owns
    /// the app-side fetch-or-create and the store cannot see it.
    private func themeRow() -> ThemeSettings? {
        (try? context.fetch(FetchDescriptor<ThemeSettings>()))?
            .sorted { $0.createdAt < $1.createdAt }.first
    }

    private func setDismissed(_ names: Set<String>) {
        let settings: ThemeSettings
        if let row = themeRow() {
            settings = row
        } else {
            settings = ThemeSettings()
            context.insert(settings)
        }
        settings.dismissedConsolesRaw = names.sorted().joined(separator: ",")
        settings.updatedAt = .now
    }

    // MARK: Writing

    /// Add a console by hand — the Dreamcast you own and have logged nothing
    /// for, which the computed shelf could never show.
    @discardableResult
    func addConsole(platform raw: String, ownership: [Ownership] = []) -> Console {
        let key = PlatformKey.canonical(raw)
        if let existing = liveConsoles().first(where: { $0.platform == key }) { return existing }
        // Adding one by hand is the clearest possible statement that you want
        // it, so it comes off the dismissed list.
        var dismissed = dismissedConsoles()
        if dismissed.remove(key) != nil { setDismissed(dismissed) }
        // A tombstoned console is revived rather than duplicated — the same
        // rule a restored game follows, and the reason Recently Deleted can
        // hand one back without leaving two.
        if let tomb = trashedConsoles().first(where: { $0.platform == key }) {
            tomb.deletedAt = nil
            if !ownership.isEmpty { tomb.ownership = ownership.map(\.rawValue) }
            touch(tomb)
            persist()
            return tomb
        }
        let console = Console(platform: key, ownership: ownership.map(\.rawValue))
        context.insert(console)
        touch(console)
        persist()
        return console
    }

    func updateConsole(_ console: Console,
                       ownership: [Ownership]? = nil,
                       variant: String? = nil,
                       acquiredAt: Date?? = nil,
                       notes: String? = nil) {
        if let ownership { console.ownership = ownership.map(\.rawValue) }
        if let variant { console.variant = variant.isEmpty ? nil : variant }
        if let acquiredAt { console.acquiredAt = acquiredAt }
        if let notes { console.notes = notes.isEmpty ? nil : notes }
        touch(console)
        persist()
    }

    /// Removing a console is also a statement that you do not want one.
    ///
    /// Without the dismissal the next pass over your library would create it
    /// again from the games — see `ThemeSettings.dismissedConsolesRaw`.
    func softDelete(_ console: Console, at date: Date = .now) {
        console.deletedAt = date
        var dismissed = dismissedConsoles()
        dismissed.insert(console.platform)
        setDismissed(dismissed)
        touch(console, at: date)
        persist()
    }

    func restore(_ console: Console) {
        console.deletedAt = nil
        var dismissed = dismissedConsoles()
        if dismissed.remove(console.platform) != nil { setDismissed(dismissed) }
        touch(console)
        persist()
    }

    func deleteForever(_ console: Console) {
        // The dismissal STAYS. Deleting forever is the strongest way to say
        // you do not want this console, and it is the one case where the
        // record itself can no longer remember that.
        context.delete(console)
        persist()
    }

    // MARK: The creation rules

    /// Rule 1 — **the first game on a platform creates the console**,
    /// inheriting that game's ownership. No prompt: there is nothing to
    /// disambiguate yet, and a dialog on the very first Genesis game would be
    /// friction for no information.
    ///
    /// Rule 2 — **a game arriving with an ownership the console lacks asks
    /// once.** The questions come back rather than being applied, because the
    /// answer is the person's; `answer(_:yes:)` records either one.
    ///
    /// Wishlist games make no consoles. A game you are waiting to buy says
    /// nothing about hardware you have, which is the same reason the systems
    /// shelf has excluded them since build 34.
    @discardableResult
    func noteConsoles(for game: Game) -> [ConsoleQuestion] {
        guard game.deletedAt == nil, game.status != .wishlist else { return [] }
        let dismissed = dismissedConsoles()
        let owned = game.ownership.compactMap(Ownership.init(rawValue:))
        var questions: [ConsoleQuestion] = []

        for platform in game.ownedPlatformNames {
            let key = PlatformKey.canonical(platform)
            guard !key.isEmpty, !dismissed.contains(key) else { continue }

            guard let console = liveConsoles().first(where: { $0.platform == key }) else {
                // Rule 1.
                let created = Console(platform: key, ownership: owned.map(\.rawValue))
                context.insert(created)
                touch(created)
                continue
            }
            // Rule 2.
            let has = Set(console.ownership)
            let declined = Set(console.declinedOwnership)
            for kind in owned where !has.contains(kind.rawValue) && !declined.contains(kind.rawValue) {
                questions.append(ConsoleQuestion(platform: key, ownership: kind, games: 1))
            }
        }
        persist()
        return questions
    }

    /// Yes adds the ownership; no records the refusal so it is never asked
    /// again. Both are answers, and the app has to keep the second one.
    func answer(_ question: ConsoleQuestion, yes: Bool) {
        guard let console = liveConsoles().first(where: { $0.platform == question.platform }) else { return }
        if yes {
            if !console.ownership.contains(question.ownership.rawValue) {
                console.ownership.append(question.ownership.rawValue)
            }
        } else if !console.declinedOwnership.contains(question.ownership.rawValue) {
            console.declinedOwnership.append(question.ownership.rawValue)
        }
        touch(console)
        persist()
    }

    /// Every question your library currently raises, counted.
    ///
    /// **This is what the migration does instead of asking N questions at
    /// once.** Back-filling silently is right — see `backfillConsoles` — but
    /// it leaves real information on the floor: eleven physical Genesis games
    /// and a console that only knows about emulation. Rather than eleven
    /// alerts, the questions wait where the consoles are, carrying the count
    /// that makes them answerable: one game is a display copy, eleven is a
    /// machine.
    func pendingConsoleQuestions(in games: [Game]) -> [ConsoleQuestion] {
        let consoles = liveConsoles()
        guard !consoles.isEmpty else { return [] }
        let byPlatform = Dictionary(consoles.map { ($0.platform, $0) }, uniquingKeysWith: { a, _ in a })
        var counts: [String: Int] = [:]   // "platform|ownership" → games

        for game in games where game.deletedAt == nil && game.status != .wishlist {
            let owned = Set(game.ownership)
            for platform in game.ownedPlatformNames {
                let key = PlatformKey.canonical(platform)
                guard let console = byPlatform[key] else { continue }
                let has = Set(console.ownership), declined = Set(console.declinedOwnership)
                for raw in owned where !has.contains(raw) && !declined.contains(raw) {
                    counts["\(key)|\(raw)", default: 0] += 1
                }
            }
        }

        return counts.compactMap { pair, count in
            let parts = pair.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2, let kind = Ownership(rawValue: parts[1]) else { return nil }
            return ConsoleQuestion(platform: parts[0], ownership: kind, games: count)
        }
        .sorted { ($0.games, $1.platform) > ($1.games, $0.platform) }
    }

    // MARK: Migration

    /// Give an existing library its consoles.
    ///
    /// **Silently, and only rule 1.** The spec left this open — ask during
    /// migration, or create and let people correct? Asking would mean a
    /// stack of questions before you have seen the feature, about consoles
    /// you have not been shown yet. So the pass creates from the EARLIEST
    /// game on each platform and inherits that game's ownership, which is
    /// what rule 1 would have done had the app always worked this way; every
    /// other game's extra ownerships become `pendingConsoleQuestions`, which
    /// wait quietly on the console itself.
    ///
    /// Idempotent: platforms that already have a console, live or dismissed,
    /// are left alone. Safe to run on every launch, and it is.
    @discardableResult
    func backfillConsoles(in games: [Game]) -> Int {
        splitJoinedPlatforms(in: games)
        refoldStoredPlatforms()
        let dismissed = dismissedConsoles()
        var known = Set(liveConsoles().map(\.platform))
        // A tombstoned console counts as known: it is in Recently Deleted
        // waiting to be restored, and recreating it beside itself would be a
        // duplicate the person never asked for.
        known.formUnion(trashedConsoles().map(\.platform))
        var created = 0

        // Earliest first, so "the first game on a platform" means the same
        // thing here as it does live.
        let ordered = games
            .filter { $0.deletedAt == nil && $0.status != .wishlist }
            .sorted { $0.addedAt < $1.addedAt }

        for game in ordered {
            let owned = game.ownership
            for platform in game.ownedPlatformNames {
                let key = PlatformKey.canonical(platform)
                guard !key.isEmpty, !known.contains(key), !dismissed.contains(key) else { continue }
                let console = Console(platform: key, ownership: owned)
                context.insert(console)
                touch(console)
                known.insert(key)
                created += 1
            }
        }
        if created > 0 { persist() }
        return created
    }

    /// **A console keeps the name it was stored under; the fold can change.**
    ///
    /// `Console.platform` holds the canonical name as it read at write time,
    /// and every lookup compares against it exactly. So when `PlatformKey`
    /// learns a new fold — Recalbox becoming Raspberry Pi, Linux becoming PC,
    /// both on 2026-09-08 — a record written yesterday keeps yesterday's name
    /// and stops matching its own tile: the console groups under the new name
    /// on Home while `console(forPlatform:)` looks for the old one and finds
    /// nothing, so the tile offers no console actions at all.
    ///
    /// `Schema.swift` says where this belongs: transforming data on a
    /// CloudKit-backed store is "an idempotent pass in app code — not a custom
    /// stage." This is that pass. Second runs do nothing, because a name that
    /// already folds to itself is not written.
    ///
    /// Where the fold merges two records into one name, the older row wins and
    /// the newer is deleted outright rather than tombstoned — it is a rename
    /// collision, not something anyone chose to throw away, and leaving it in
    /// Recently Deleted would offer to restore a duplicate.
    /// **Undo a CSV import's joined platform names.**
    ///
    /// The 09-11 import read Gamery's `Xbox,Mac` as ONE platform and stored it
    /// on the game and as a console of its own. Split back into the systems
    /// the cell named — the game owned on each — and the joined console goes,
    /// deleted outright rather than tombstoned: nobody chose it, and the
    /// backfill below creates the real ones from the games. One that has had
    /// a photograph added is renamed to its first system instead, keeping it.
    /// Idempotent: nothing is written once no name holds a comma.
    private func splitJoinedPlatforms(in games: [Game]) {
        var changed = false
        func split(_ list: [String]) -> [String] {
            var seen = Set<String>()
            return list.flatMap { CSVImport.splitPlatforms($0) }.filter { seen.insert($0).inserted }
        }
        for game in games where game.platforms.contains(where: { $0.contains(",") })
            || (game.ownedPlatforms ?? []).contains(where: { $0.contains(",") }) {
            game.platforms = split(game.platforms)
            if let owned = game.ownedPlatforms { game.ownedPlatforms = split(owned) }
            changed = true
        }
        for console in liveConsoles() + trashedConsoles() where console.platform.contains(",") {
            if (console.images ?? []).isEmpty {
                context.delete(console)
            } else if let first = CSVImport.splitPlatforms(console.platform).first {
                console.platform = PlatformKey.canonical(first)
                touch(console)
            }
            changed = true
        }
        if changed { persist() }
    }

    private func refoldStoredPlatforms() {
        var changed = false
        var byName: [String: Console] = [:]
        // Oldest first, so the record that has been there longest is the one
        // that keeps its ownership, notes and photos through a merge.
        for console in (liveConsoles() + trashedConsoles()).sorted(by: { $0.createdAt < $1.createdAt }) {
            let folded = PlatformKey.canonical(console.platform)
            if let winner = byName[folded] {
                if console.deletedAt == nil && winner.deletedAt != nil { winner.deletedAt = nil }
                context.delete(console)
                changed = true
                continue
            }
            if folded != console.platform {
                console.platform = folded
                touch(console)
                changed = true
            }
            byName[folded] = console
        }
        if changed { persist() }
    }
}
