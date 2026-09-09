import Foundation

/// **Which model of a console you actually own.**
///
/// The app draws one render per platform, chosen when the art was
/// commissioned — so a Saturn is the black North American machine, a Genesis
/// is a Model 2, a Game Boy is the 1989 DMG. Those are reasonable defaults and
/// wrong for a lot of people, and the point of the console record is that it is
/// *your* machine.
///
/// `ThemeSettings.platformIconVariantsData` has been deployed since Schema V2
/// and read by nothing since. This is what it was deployed for.
///
/// **Variant art is deliberately outside the `platform-` namespace.** Two
/// invariants enumerate the asset catalog for `platform-*` imagesets and
/// require every one to carry a release year and a maker; a variant is the
/// same console in a different shell, so it has neither of its own and must
/// not be swept up by those checks. It also means `PlatformIcon.assetName`
/// keeps returning the same slug whatever you pick — which matters, because
/// that slug is the console's IDENTITY (`consoleKey`) and the key its release
/// year is looked up under. Only the drawing changes.
enum PlatformVariant {

    /// One shell of one machine.
    struct Variant: Identifiable, Hashable {
        /// Stored in `platformIconVariantsData`. Never rename one — a stored
        /// key that no longer resolves falls back to the default, silently
        /// undoing somebody's choice.
        let key: String
        /// What the picker calls it.
        let label: String
        /// The line under the label: what tells the two apart at a glance.
        let detail: String
        /// The imageset, or nil for the variant the app already ships.
        let asset: String?

        var id: String { key }
    }

    /// Keyed by the CANONICAL platform name, so every spelling of a console
    /// resolves to the same list.
    ///
    /// The first entry of each list is the machine the app already draws, and
    /// its `asset` is nil rather than a copy of the shipped slug — the default
    /// is "whatever `PlatformIcon.assetName` says", so re-commissioning a
    /// console's main render never leaves a stale duplicate here.
    static let catalog: [String: [Variant]] = [
        // The only pair with both renders drawn as of 2026-09-08. The Japanese
        // Saturn is gray and launched a season earlier; the machine that
        // reached the US was black. Both were "Model 1".
        "Saturn": [
            Variant(key: "na", label: "North America",
                    detail: "Black, 1995", asset: nil),
            Variant(key: "jp", label: "Japan",
                    detail: "Gray, 1994", asset: "variant-saturn-jp"),
        ],
        // **"Mac" is forty years of very different objects.** The app draws
        // the machine you would buy today; the other three were already drawn
        // and sitting unused in the art archive. Tim, 2026-09-08: *"There are
        // at least 2 other Mac icons (bondi blue, and then an older Mac that I
        // can't remember which)."* The older one is a compact Macintosh.
        "Mac": [
            Variant(key: "mini", label: "Mac mini",
                    detail: "Silver, 2024", asset: nil),
            Variant(key: "imac", label: "iMac",
                    detail: "M-series, 2021", asset: "variant-mac-imac"),
            Variant(key: "imac-g3", label: "iMac G3",
                    detail: "Bondi Blue, 1998", asset: "variant-mac-imac-g3"),
            Variant(key: "powerbook", label: "PowerBook 540c",
                    detail: "Dark grey, 1994", asset: "variant-mac-powerbook"),
            Variant(key: "lc", label: "Macintosh LC III",
                    detail: "Pizza box, 1993", asset: "variant-mac-lc"),
            Variant(key: "compact", label: "Macintosh",
                    detail: "Compact, 1984", asset: "variant-mac-compact"),
        ],
        // **A PC is one machine continuously rebuilt for forty years**, which
        // is why the modern RGB tower alone was wrong for anyone whose PC
        // gaming started before it. DOS is a separate console rather than a
        // variant here — see `PlatformIcon.assetName` — because that is an
        // era, and these are shells.
        "PC": [
            Variant(key: "modern", label: "Gaming tower",
                    detail: "RGB, today", asset: nil),
            Variant(key: "laptop", label: "Gaming laptop",
                    detail: "2020", asset: "variant-pc-laptop"),
            Variant(key: "black", label: "Black tower",
                    detail: "2007, before RGB", asset: "variant-pc-black"),
            Variant(key: "beige", label: "Beige desktop",
                    detail: "1999", asset: "variant-pc-beige"),
            Variant(key: "486", label: "486 tower",
                    detail: "1993", asset: "variant-pc-486"),
        ],
        // Nintendo sold the Color in a shelf of colors, and the grape one the
        // app draws is only the one that got commissioned first.
        "GBC": [
            Variant(key: "grape", label: "Grape",
                    detail: "Purple, 1998", asset: nil),
            Variant(key: "dandelion", label: "Dandelion",
                    detail: "Yellow, 1998", asset: "variant-gbc-yellow"),
        ],
        // A phone is a phone, and which one is entirely a matter of whose you
        // hold. The app draws a Galaxy because something had to be drawn.
        "Android": [
            Variant(key: "galaxy", label: "Galaxy",
                    detail: "Samsung", asset: nil),
            Variant(key: "pixel", label: "Pixel",
                    detail: "Google", asset: "variant-android-pixel"),
        ],
    ]

    /// The variants for a platform, or an empty list where there is only one
    /// machine to draw. The picker uses emptiness to decide whether to appear
    /// at all, so a console with nothing to choose shows no choice.
    static func variants(for platform: String) -> [Variant] {
        catalog[PlatformKey.canonical(platform)] ?? []
    }

    // MARK: The machines you have had

    /// **Where the lineage hides in a map of single choices.**
    ///
    /// `platformIconVariantsData` is one variant key per platform, and it is
    /// deployed — changing its SHAPE would mean an older build failing to
    /// decode it. So the lineage rides in the same map under a key no platform
    /// can ever be called: a leading `#`. An older build sees an entry for a
    /// platform named "#had:Mac", finds no console by that name, and ignores
    /// it. No promote, no migration, nothing to break.
    private static func lineageKey(_ platform: String) -> String {
        "#had:" + PlatformKey.canonical(platform)
    }

    /// The machines someone says they have had, oldest first — the order the
    /// catalog lists them in, which is newest-to-oldest reversed, because a
    /// lineage reads forward in time.
    ///
    /// The drawn one is always included whether or not it was ticked: it is on
    /// the shelf, so claiming otherwise on the page below would contradict the
    /// tile above.
    static func owned(for platform: String, in map: [String: String]) -> [Variant] {
        let list = variants(for: platform)
        guard !list.isEmpty else { return [] }
        var ticked = Set((map[lineageKey(platform)] ?? "")
            .split(separator: ",").map(String.init))
        if let drawn = variant(for: platform, key: map[PlatformKey.canonical(platform)]) {
            ticked.insert(drawn.key)
        }
        return list.reversed().filter { ticked.contains($0.key) }
    }

    /// Write the ticked set. Stored in catalog order rather than tap order, so
    /// the row reads the same however someone got there.
    static func setOwned(_ keys: Set<String>, for platform: String,
                         in map: inout [String: String]) {
        let ordered = variants(for: platform).map(\.key).filter { keys.contains($0) }
        if ordered.isEmpty { map.removeValue(forKey: lineageKey(platform)) }
        else { map[lineageKey(platform)] = ordered.joined(separator: ",") }
    }

    /// Just the keys, for a picker that needs to know what is ticked.
    static func ownedKeys(for platform: String, in map: [String: String]) -> Set<String> {
        Set((map[lineageKey(platform)] ?? "").split(separator: ",").map(String.init))
    }

    /// The variant a stored key names, or the default when it names nothing —
    /// which is what a key written by a newer build, or by a build that had
    /// art this one does not, resolves to.
    static func variant(for platform: String, key: String?) -> Variant? {
        let list = variants(for: platform)
        guard let key, let found = list.first(where: { $0.key == key }) else {
            return list.first
        }
        return found
    }
}
