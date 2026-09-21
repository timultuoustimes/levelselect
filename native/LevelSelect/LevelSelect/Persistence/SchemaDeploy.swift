import Foundation

/// Fields added to the store that CloudKit Production may not have yet.
///
/// A build that WRITES a field Production doesn't have breaks sync for every
/// record carrying it. So a feature built on a new field stays out of reach on
/// a Production build until the schema is deployed there — then this flag
/// flips, in the same commit as the note that says it was deployed. A
/// Development build (the simulator, a seeding run) always has it, which is
/// how the feature gets built and tested before the deploy.
enum SchemaDeploy {
    /// `TrackerStateRecord.valuesJSON`, `Console.nickname`,
    /// `ThemeSettings.heroHexLight/heroHexDark` — build 39.
    ///
    /// ⚠️ Flip to true only once Tim has deployed them to Production and the
    /// Console diff showed all four.
    /// Deployed 2026-09-17 by Tim; the Development-vs-Production diff he
    /// pasted that morning listed exactly these four fields.
    static let build39DeployedToProduction = true

    /// `NewsFeed` and `NewsItemState`, plus `ThemeSettings.suggestionPrefsRaw`,
    /// `ThemeSettings.shelfOrderRaw` and `Game.barcodes` — schema V7, the
    /// second build 39 promote (news reader, synced suggestion preferences,
    /// manual shelf order, ScanDex barcodes).
    ///
    /// ⚠️ Flip to true only once Tim has deployed them to Production and the
    /// Console diff showed all five.
    /// Deployed 2026-09-18 by Tim, seeded from the Mac on a throwaway
    /// `seed.store` (`-LSSeedStore YES`); the Development-vs-Production diff
    /// he pasted listed exactly these five and nothing else.
    static let v7DeployedToProduction = true

    /// `Playthrough.carriedOverSpansData` — schema V8, build 40: which years
    /// a lump of imported playtime belongs to (`CarriedOverSpan`).
    ///
    /// ⚠️ Flip to true only once Tim has deployed it to Production and the
    /// Console diff showed it. Until then the app keeps the single-year
    /// tagging, which rides on `Playthrough.startedAt` — deployed since V1.
    static let v8DeployedToProduction = false

    static var v8Fields: Bool {
        v8DeployedToProduction || !syncsToProduction
    }

    static var v7Fields: Bool {
        v7DeployedToProduction || !syncsToProduction
    }

    static var build39Fields: Bool {
        build39DeployedToProduction || !syncsToProduction
    }

    /// From Info.plist, set by `LS_CK_ENV`. Unknown reads as Production — the
    /// safe answer, since a false "Development" is what would break sync.
    static var syncsToProduction: Bool {
        let env = Bundle.main.object(forInfoDictionaryKey: "LSCloudKitEnvironment") as? String
        return env != "Development"
    }
}
