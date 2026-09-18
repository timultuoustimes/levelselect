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
        /// When this shell came out, which is the order a lineage reads in.
        /// The catalog can't carry that order itself: its first entry has to
        /// be the machine the app draws, and that is sometimes the newest (a
        /// Mac mini) and sometimes the oldest (a front-loading NES). Nil for a
        /// choice that isn't a point in time, like which phone you hold.
        var year: Int? = nil

        var id: String { key }
        /// For a second list of the same machines in the same Form, whose rows
        /// must not share identities with the first. See `ConsoleEditor`.
        var lineageRowID: String { "had:" + key }
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
                    detail: "Black, 1995", asset: nil, year: 1995),
            Variant(key: "jp", label: "Japan",
                    detail: "Gray, 1994", asset: "variant-saturn-jp", year: 1994),
        ],
        // **"Mac" is forty years of very different objects.** The app draws
        // the machine you would buy today; the other three were already drawn
        // and sitting unused in the art archive. Tim, 2026-09-08: *"There are
        // at least 2 other Mac icons (bondi blue, and then an older Mac that I
        // can't remember which)."* The older one is a compact Macintosh.
        "Mac": [
            Variant(key: "mini", label: "Mac mini",
                    detail: "Silver, 2024", asset: nil, year: 2024),
            Variant(key: "imac", label: "iMac",
                    detail: "M-series, 2021", asset: "variant-mac-imac", year: 2021),
            Variant(key: "imac-g3", label: "iMac G3",
                    detail: "Bondi Blue, 1998", asset: "variant-mac-imac-g3", year: 1998),
            Variant(key: "powerbook", label: "PowerBook 540c",
                    detail: "Dark gray, 1994", asset: "variant-mac-powerbook", year: 1994),
            Variant(key: "lc", label: "Macintosh LC III",
                    detail: "Pizza box, 1993", asset: "variant-mac-lc", year: 1993),
            Variant(key: "compact", label: "Macintosh",
                    detail: "Compact, 1984", asset: "variant-mac-compact", year: 1984),
        ],
        // **A PC is one machine continuously rebuilt for forty years**, which
        // is why the modern RGB tower alone was wrong for anyone whose PC
        // gaming started before it. DOS is a separate console rather than a
        // variant here — see `PlatformIcon.assetName` — because that is an
        // era, and these are shells.
        "PC": [
            Variant(key: "modern", label: "Gaming tower",
                    detail: "RGB, today", asset: nil, year: 2024),
            Variant(key: "laptop", label: "Gaming laptop",
                    detail: "2020", asset: "variant-pc-laptop", year: 2020),
            Variant(key: "black", label: "Black tower",
                    detail: "2007, before RGB", asset: "variant-pc-black", year: 2007),
            Variant(key: "beige", label: "Beige desktop",
                    detail: "1999", asset: "variant-pc-beige", year: 1999),
            Variant(key: "486", label: "486 tower",
                    detail: "1993", asset: "variant-pc-486", year: 1993),
        ],
        // **The SP was the default until 2026-09-09**, which meant the app
        // drew a 2003 clamshell for a console people picture as the 2001
        // landscape slab. Codex drew the original that day; the SP keeps its
        // render as the variant it always should have been.
        "GBA": [
            Variant(key: "agb", label: "Game Boy Advance",
                    detail: "Indigo, 2001", asset: nil, year: 2001),
            Variant(key: "glacier", label: "Game Boy Advance",
                    detail: "Glacier", asset: "variant-gba-glacier"),
            Variant(key: "fuchsia", label: "Game Boy Advance",
                    detail: "Fuchsia", asset: "variant-gba-fuchsia"),
            Variant(key: "arctic", label: "Game Boy Advance",
                    detail: "Arctic", asset: "variant-gba-arctic"),
            Variant(key: "black", label: "Game Boy Advance",
                    detail: "Black", asset: "variant-gba-black"),
            Variant(key: "gba-platinum", label: "Game Boy Advance",
                    detail: "Platinum", asset: "variant-gba-platinum"),
            // **The SP's colors sit in the same list.** A variant has no
            // variants of its own, and a flat list is the honest shape: the
            // question is "which one do you have", and a Flame SP is an
            // answer to it.
            Variant(key: "sp", label: "Game Boy Advance SP",
                    detail: "Silver clamshell, 2003", asset: "variant-gba-sp", year: 2003),
            Variant(key: "sp-cobalt", label: "Game Boy Advance SP",
                    detail: "Cobalt", asset: "variant-gba-sp-cobalt"),
            Variant(key: "sp-flame", label: "Game Boy Advance SP",
                    detail: "Flame", asset: "variant-gba-sp-flame"),
            Variant(key: "sp-onyx", label: "Game Boy Advance SP",
                    detail: "Onyx", asset: "variant-gba-sp-onyx"),
            Variant(key: "sp-pearl", label: "Game Boy Advance SP",
                    detail: "Pearl Pink", asset: "variant-gba-sp-pearl"),
            Variant(key: "sp-nes", label: "Game Boy Advance SP",
                    detail: "NES Classic Edition", asset: "variant-gba-sp-nes"),
        ],
        // Nintendo sold the Color in a shelf of colors, and the grape one the
        // app draws is only the one that got commissioned first.
        // Nintendo sold the Color in a shelf of colors; the app draws Grape
        // because that is the one that got commissioned first.
        "GBC": [
            Variant(key: "grape", label: "Grape",
                    detail: "Purple, 1998", asset: nil),
            Variant(key: "dandelion", label: "Dandelion",
                    detail: "Yellow, 1998", asset: "variant-gbc-yellow"),
            Variant(key: "berry", label: "Berry",
                    detail: "Magenta, 1998", asset: "variant-gbc-berry"),
            Variant(key: "kiwi", label: "Kiwi",
                    detail: "Green, 1998", asset: "variant-gbc-kiwi"),
            Variant(key: "teal", label: "Teal",
                    detail: "Blue-green, 1998", asset: "variant-gbc-teal"),
            Variant(key: "atomic", label: "Atomic Purple",
                    detail: "Clear, 1999", asset: "variant-gbc-atomic"),
        ],

        // **The Play It Loud! shelf.** The app draws the 1989 gray brick; the
        // colors came in 1995 and are what a lot of people actually carried.
        "Game Boy": [
            Variant(key: "dmg", label: "Game Boy",
                    detail: "Gray, 1989", asset: nil, year: 1989),
            Variant(key: "red", label: "Play It Loud! Red",
                    detail: "1995", asset: "variant-gameboy-red", year: 1995),
            Variant(key: "yellow", label: "Play It Loud! Yellow",
                    detail: "1995", asset: "variant-gameboy-yellow", year: 1995),
            Variant(key: "green", label: "Play It Loud! Green",
                    detail: "1995", asset: "variant-gameboy-green", year: 1995),
            Variant(key: "black", label: "Play It Loud! Black",
                    detail: "1995", asset: "variant-gameboy-black", year: 1995),
            Variant(key: "clear", label: "Play It Loud! Clear",
                    detail: "See-through, 1995", asset: "variant-gameboy-clear", year: 1995),
        ],

        // **Funtastic, and the machine that came before it.** The app draws
        // the translucent Jungle Green; charcoal is the 1996 original.
        "N64": [
            Variant(key: "jungle", label: "Jungle Green",
                    detail: "Translucent, 1999", asset: nil, year: 1999),
            Variant(key: "charcoal", label: "Nintendo 64",
                    detail: "Charcoal gray, 1996", asset: "variant-n64-charcoal", year: 1996),
            Variant(key: "atomic", label: "Atomic Purple",
                    detail: "Clear", asset: "variant-n64-atomic"),
            Variant(key: "grape", label: "Grape Purple",
                    detail: "Funtastic", asset: "variant-n64-grape"),
            Variant(key: "fire", label: "Fire Orange",
                    detail: "Funtastic", asset: "variant-n64-fire"),
            Variant(key: "ice", label: "Ice Blue",
                    detail: "Funtastic", asset: "variant-n64-ice"),
            Variant(key: "smoke", label: "Smoke Black",
                    detail: "Funtastic", asset: "variant-n64-smoke"),
            Variant(key: "watermelon", label: "Watermelon Red",
                    detail: "Funtastic", asset: "variant-n64-watermelon"),
            Variant(key: "gold", label: "Gold",
                    detail: "Limited edition", asset: "variant-n64-gold"),
        ],

        // **One platform, three machines.** The app draws the 2017 hybrid with
        // its neon Joy-Cons; the Lite is a different object entirely (no
        // Joy-Cons, no dock) and the OLED is the one most people bought last.
        "Switch": [
            Variant(key: "neon", label: "Nintendo Switch",
                    detail: "Neon Joy-Cons, 2017", asset: nil, year: 2017),
            Variant(key: "oled-white", label: "Switch OLED",
                    detail: "White, 2021", asset: "variant-switch-oled-white", year: 2021),
            Variant(key: "oled-mario", label: "Switch OLED",
                    detail: "Mario Red, 2023", asset: "variant-switch-oled-mario", year: 2023),
            Variant(key: "docked", label: "Nintendo Switch",
                    detail: "Docked, with a Pro Controller", asset: "variant-switch-docked"),
            Variant(key: "gray", label: "Nintendo Switch",
                    detail: "Gray Joy-Cons, 2017", asset: "variant-switch-gray", year: 2017),
            Variant(key: "purple-orange", label: "Nintendo Switch",
                    detail: "Neon purple and orange", asset: "variant-switch-purple-orange"),
            Variant(key: "yellow", label: "Nintendo Switch",
                    detail: "Neon yellow", asset: "variant-switch-yellow"),
            Variant(key: "pink-green", label: "Nintendo Switch",
                    detail: "Neon pink and green", asset: "variant-switch-pink-green"),
            Variant(key: "mario", label: "Mario Red & Blue",
                    detail: "2021", asset: "variant-switch-mario", year: 2021),
            Variant(key: "animal-crossing", label: "Animal Crossing",
                    detail: "Pastel, 2020", asset: "variant-switch-animal-crossing", year: 2020),
            Variant(key: "lite-yellow", label: "Switch Lite",
                    detail: "Yellow, 2019", asset: "variant-switch-lite-yellow", year: 2019),
            Variant(key: "lite-turquoise", label: "Switch Lite",
                    detail: "Turquoise, 2019", asset: "variant-switch-lite-turquoise", year: 2019),
            Variant(key: "lite-gray", label: "Switch Lite",
                    detail: "Gray, 2019", asset: "variant-switch-lite-gray", year: 2019),
            Variant(key: "lite-coral", label: "Switch Lite",
                    detail: "Coral, 2020", asset: "variant-switch-lite-coral", year: 2020),
            Variant(key: "lite-blue", label: "Switch Lite",
                    detail: "Blue, 2021", asset: "variant-switch-lite-blue", year: 2021),
        ],

        "GameCube": [
            Variant(key: "indigo", label: "Indigo",
                    detail: "2001", asset: nil, year: 2001),
            Variant(key: "black", label: "Jet Black",
                    detail: "2001", asset: "variant-gamecube-black", year: 2001),
            Variant(key: "platinum", label: "Platinum",
                    detail: "Silver, 2002", asset: "variant-gamecube-platinum", year: 2002),
            Variant(key: "spice", label: "Spice",
                    detail: "Orange, Japan", asset: "variant-gamecube-spice"),
        ],

        "DS": [
            Variant(key: "white", label: "Polar White",
                    detail: "DS Lite, 2006", asset: nil, year: 2006),
            Variant(key: "onyx", label: "Onyx",
                    detail: "DS Lite", asset: "variant-ds-onyx"),
            Variant(key: "cobalt", label: "Cobalt & Black",
                    detail: "DS Lite", asset: "variant-ds-cobalt"),
            Variant(key: "crimson", label: "Crimson & Black",
                    detail: "DS Lite", asset: "variant-ds-crimson"),
            Variant(key: "coral", label: "Coral Pink",
                    detail: "DS Lite", asset: "variant-ds-coral"),
        ],

        "3DS": [
            Variant(key: "aqua", label: "Aqua Blue",
                    detail: "2011", asset: nil, year: 2011),
            Variant(key: "black", label: "Cosmo Black",
                    detail: "2011", asset: "variant-3ds-black", year: 2011),
            Variant(key: "red", label: "Flame Red",
                    detail: "2011", asset: "variant-3ds-red", year: 2011),
            Variant(key: "purple", label: "Midnight Purple",
                    detail: "2012", asset: "variant-3ds-purple", year: 2012),
            Variant(key: "pink", label: "Pearl Pink",
                    detail: "2012", asset: "variant-3ds-pink", year: 2012),
        ],
        // **Nintendo's cost-reduced redesigns**, both drawn 2026-09-10 and both
        // the machine a lot of people actually had: the top-loader was the NES
        // still on shelves in 1993, and the Jr. was the SNES Nintendo sold
        // through the N64's first years. The originals stay the default.
        "SNES": [
            Variant(key: "original", label: "Super NES",
                    detail: "Original, 1991", asset: nil, year: 1991),
            Variant(key: "jr", label: "SNES Jr.",
                    detail: "SNS-101, 1997", asset: "variant-snes-jr", year: 1997),
        ],
        // The Model 2 has been the Genesis icon since the first set shipped;
        // the Model 1, with its big round slot and 16-BIT lettering, is the
        // one a lot of people plugged in first. Drawn 2026-09-10.
        "Genesis": [
            Variant(key: "model-2", label: "Genesis Model 2",
                    detail: "Compact, 1993", asset: nil, year: 1993),
            Variant(key: "model-1", label: "Genesis Model 1",
                    detail: "Original, 1989", asset: "variant-genesis-model-1", year: 1989),
        ],
        "NES": [
            Variant(key: "front-loader", label: "NES",
                    detail: "Front-loader, 1985", asset: nil, year: 1985),
            Variant(key: "top-loader", label: "NES-101",
                    detail: "Top-loader, 1993", asset: "variant-nes-101", year: 1993),
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

    /// The machines someone says they have had, oldest first, because a
    /// lineage reads forward in time. Ordered by `year`, not by catalog
    /// position: reversing the catalog read the GBA as SP-then-original.
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
        return list.enumerated()
            .filter { ticked.contains($0.element.key) }
            .sorted { a, b in
                switch (a.element.year, b.element.year) {
                case let (x?, y?) where x != y: return x < y
                default: return a.offset > b.offset
                }
            }
            .map(\.element)
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
