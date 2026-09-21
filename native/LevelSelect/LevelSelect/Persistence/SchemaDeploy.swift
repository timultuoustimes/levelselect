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

    /// Build 40's field batch: `Playthrough.carriedOverSpansData` (which
    /// years a lump of imported playtime belongs to — `CarriedOverSpan`),
    /// `ThemeSettings.nameFontRaw`, and `anniversaryReminder` on both
    /// `Memory` and `CompletionEvent`. The last three ship ahead of their
    /// features, by the V5 rule: an unused optional costs nothing and a
    /// promote costs a cycle.
    ///
    /// Deployed 2026-09-21 by Tim, seeded from the Mac on a throwaway
    /// `seed.store` (`-LSSeedStore YES`, verified with `lsof` — only the seed
    /// store was ever open, the group container's `default.store` never).
    /// The Development-vs-Production diff he pasted listed exactly these four
    /// and nothing else: `carriedOverSpansData` as BYTES rather than ASSET,
    /// both switches as INT64, `nameFontRaw` as STRING, no record type added
    /// and no field dropped. Purged afterwards.
    static let v8DeployedToProduction = true

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
