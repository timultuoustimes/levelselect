import Foundation

/// One term the tag picker can offer.
///
/// `id` is an internal resource identifier and never leaves the bundle — what
/// a game stores is `name`, an ordinary string. That separation is the whole
/// design: **taxonomy identity is the app's concern, stored tag text is
/// yours.** If v2 decides the preferred spelling is "Souls-like", your
/// existing "Soulslike" is not rewritten; the vocabulary carries the other
/// spelling as an alias so search and suggestion still treat them as one idea.
struct SuggestedTag: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let category: String
    let aliases: [String]

    /// Everything this term answers to, for matching what someone typed.
    var searchTerms: [String] { [name] + aliases }
}

/// A bundled vocabulary for the tag picker. **Stage 2 of the taxonomy work.**
///
/// **Nothing here is ever applied on your behalf.** A suggestion becomes a tag
/// when you tap it, and from that moment it is an ordinary `userTags` string —
/// indistinguishable from one you typed, with no provenance to store, no
/// confidence to record, and nothing to un-apply. That is what removed the
/// entire repair problem the first proposal needed: LevelSelect decides a game
/// is a Soulslike, you disagree, and now the app has to remember that it was
/// wrong, sync that, and tell "removed by hand" apart from "metadata changed".
/// A picker with a vocabulary has none of that.
///
/// **A static resource, not synced data.** No CloudKit record type, no field,
/// no schema deploy — the only synced thing stays `userTags: [String]`, which
/// already existed and was already filterable. Two app versions can carry
/// different vocabularies without making a library incompatible.
///
/// **Curated around where IGDB stops answering the question.** IGDB calling
/// Hollow Knight, Celeste and Super Meat Boy all "Platform / Adventure / Indie"
/// is the case this exists for. So terms IGDB already carries as a GENRE are
/// deliberately absent — MOBA, RTS, Visual Novel, Point-and-click, Quiz/Trivia,
/// Card & Board Game, Pinball, and "Hack and slash/Beat 'em up" are all IGDB
/// genres, and repeating them here would offer you a word you can already
/// browse from the genre shelf. Rhythm is out for the same reason: IGDB calls
/// it Music.
///
/// **Stop when it is enough.** If forty terms cover ninety percent of what you
/// reach for, that is the finished feature. There is no prize for 415 — a small
/// opinionated vocabulary is the product advantage here, because Steam needs
/// hundreds for discovery across millions of users and this needs enough for
/// one person to organize what they own.
enum SuggestedTags {

    /// Decoded once. A missing or damaged file is an empty vocabulary rather
    /// than a crash: the picker's own free text and the library's existing
    /// words both still work, so the feature degrades to what it replaced.
    static let all: [SuggestedTag] = {
        guard let url = Bundle.main.url(forResource: "SuggestedTags", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data)
        else { return [] }
        return file.tags
    }()

    private struct File: Codable { let version: Int; let tags: [SuggestedTag] }

    /// Grouped for browsing, categories in first-appearance order so the file
    /// itself decides the order rather than an alphabetical accident.
    static var byCategory: [(category: String, tags: [SuggestedTag])] {
        var order: [String] = []
        var groups: [String: [SuggestedTag]] = [:]
        for tag in all {
            if groups[tag.category] == nil { order.append(tag.category) }
            groups[tag.category, default: []].append(tag)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }

    /// Terms matching what someone has typed, aliases included.
    ///
    /// Matching an alias offers the CANONICAL name — typing "souls-like" gets
    /// you "Soulslike", which is how the vocabulary stops one idea fragmenting
    /// into three spellings across a library.
    static func matching(_ typed: String) -> [SuggestedTag] {
        let query = typed.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "#", with: "")
        guard !query.isEmpty else { return [] }
        return all.filter { tag in
            tag.searchTerms.contains { term in
                term.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
    }

    /// The canonical spelling for a word, if the vocabulary knows one.
    ///
    /// Used for READING — searching and offering — never for writing. A tag
    /// already in a library is never rewritten to match.
    static func canonical(_ text: String) -> String? {
        let query = text.trimmingCharacters(in: .whitespaces)
        return all.first { tag in
            tag.searchTerms.contains { $0.caseInsensitiveCompare(query) == .orderedSame }
        }?.name
    }
}
