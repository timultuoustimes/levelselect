import Testing
import Foundation
@testable import LevelSelect

/// Five real community sheets, three shapes: a checkbox grid (Hollow Knight,
/// The Witcher 3), the same header over block after block (Final Fantasy VII,
/// The Witcher 3's trophies), and ordinary tables (Persona 5). Tim, 09-17:
/// "Let's test some other sheets, some with and without tabs."
struct CommunitySheetsTests {

    private func parse(_ csv: String) -> [TrackerListParser.ParsedCategory] {
        TrackerListParser.parse(SheetsLinkImport.markdownTable(fromCSV: csv)).categories
    }

    private func list(_ categories: [TrackerListParser.ParsedCategory], _ name: String)
        -> TrackerListParser.ParsedCategory? {
        categories.first { $0.name == name }
    }

    @Test("Hollow Knight: every titled list, box-first, with shards as counters")
    func hollowKnight() throws {
        let cats = parse(CommunitySheetFixtures.hollowKnight)
        #expect(cats.map(\.name).starts(with: ["Charms", "Bosses", "Equipment", "Spells"]))
        #expect(list(cats, "Charms")?.items.count == 40)
        #expect(list(cats, "Bosses")?.items.first?.name == "Broken Vessel")
        let masks = try #require(list(cats, "Mask Shards"))
        #expect(masks.items.first?.countTarget == 5, "one box for the upgrade and four for its shards")
        #expect(list(cats, "Nail Arts")?.items.first?.detail == "Nailmaster Sheo")
        #expect(list(cats, "Godhome")?.items.first?.name == "Find Godhome")
        #expect(!cats.contains { $0.name == "Imported" || $0.name.isEmpty })
    }

    @Test("Final Fantasy VII: block after block becomes lists by category, placed by area")
    func finalFantasy7() throws {
        let cats = parse(CommunitySheetFixtures.finalFantasy7)
        #expect(cats.map(\.name).starts(with: ["Basic", "Treasure"]))
        let treasure = try #require(list(cats, "Treasure"))
        #expect(treasure.items.first?.name == "Restore Materia")
        #expect(treasure.items.first?.location == "1st Reactor")
        #expect(treasure.items.first?.detail?.hasPrefix("Bottom of the reactor") == true)
        // The filter panel at the top ("Treasure TRUE") is not an item.
        #expect(!cats.flatMap(\.items).contains { $0.name == "Treasure" || $0.name == "Steals" })
    }

    @Test("The Witcher 3: regions over list titles, name-first boxes, formulas ignored")
    func witcherQuests() throws {
        let cats = parse(CommunitySheetFixtures.witcherQuests)
        #expect(cats.map(\.name).starts(with: ["Main Quests", "Side Quests", "Contracts", "Treasure Hunts"]))
        let main = try #require(list(cats, "Main Quests"))
        #expect(main.items.first?.name == "Kaer Morhen (1)")
        #expect(main.items.first?.location == "Prologue & White Orchard")
        #expect(!cats.flatMap(\.items).contains { $0.location?.contains("%") == true })
        #expect(!cats.contains { $0.name.hasPrefix("Interactive map") }, "link rows at the top aren't titles")
    }

    @Test("The Witcher 3 quest order: a table with an unnamed Done column, and no contents rows")
    func witcherOrder() throws {
        let cats = parse(CommunitySheetFixtures.witcherOrder)
        let quests = try #require(cats.first)
        #expect(quests.items.first?.name == "Kaer Morhen (1)")
        #expect(quests.items.first?.location == "KAER MORHEN")
        #expect(!quests.items.contains { $0.name == "VIZIMA" || $0.name == "SIDE QUESTS" })
    }

    @Test("The Witcher 3 scavenger hunts: each hunt a list, its parts as places, pairs of boxes as counters")
    func witcherScavenger() throws {
        let cats = parse(CommunitySheetFixtures.witcherScavenger)
        #expect(cats.map(\.name).starts(with: ["Bear (Ursine) Scavenger Hunt", "Cat (Feline) Scavenger Hunt"]))
        let bear = try #require(cats.first)
        let armor = try #require(bear.items.first { $0.name == "Superior Armor" })
        #expect(armor.location == "Part 3")
        #expect(armor.countTarget == 2)
    }

    @Test("The Witcher 3 trophies: repeated Name/Requirement blocks, MISSABLE read as a flag")
    func witcherTrophies() throws {
        let cats = parse(CommunitySheetFixtures.witcherTrophies)
        let trophies = try #require(cats.first)
        #expect(trophies.items.count > 60)
        #expect(trophies.items.first?.location == "Base Game Trophies")
        let assassin = try #require(trophies.items.first { $0.name == "Assassin of Kings" })
        #expect(assassin.missable)
        #expect(Set(trophies.items.compactMap(\.location)).count >= 2)
    }

    @Test("The Witcher 3 Gwent: factions from multi-line titles, copies as counters, ticks kept")
    func witcherGwent() throws {
        let cats = parse(CommunitySheetFixtures.witcherGwent)
        #expect(cats.map(\.name).starts(with: ["Northern Realms", "Nilfgaard"]))
        let commando = try #require(cats.first?.items.first)
        #expect(commando.name == "Blue Stripes Commando")
        #expect(commando.countTarget == 3 && commando.count == 3 && commando.done)
    }

    @Test("Persona 5: side-by-side tables split, and Personas group by Arcana, not Level")
    func persona5() throws {
        let info = parse(CommunitySheetFixtures.persona5Info)
        #expect(info.map(\.name).starts(with: ["Book Title", "Game Title"]))
        #expect(info.first?.items.first?.name == "Pirate Legend")
        #expect(info.dropFirst().first?.items.first?.name == "Star Forneus")
        let personas = try #require(parse(CommunitySheetFixtures.persona5Personas).first)
        #expect(personas.items.first?.name == "Agathion")
        #expect(personas.items.first?.location == "Chariot")
    }

    @Test("Tick values")
    func ticks() {
        #expect(TrackerListParser.progress(from: "TRUE").done)
        #expect(!TrackerListParser.progress(from: "FALSE").done)
        let partial = TrackerListParser.progress(from: "2/4")
        #expect(partial.count == 2 && partial.target == 4 && !partial.done)
        #expect(TrackerListParser.isTickValue("no"))
        #expect(!TrackerListParser.isTickValue("WHITE ORCHARD"))
        #expect(SheetsLinkImport.clean("A B      A B      A B") == "A B")
        #expect(SheetsLinkImport.isFormula("QUEST COMPLETION =     0%"))
        #expect(TrackerListParser.titled("PROLOGUE & WHITE ORCHARD") == "Prologue & White Orchard")
    }
}
