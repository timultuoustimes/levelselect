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
        // Saturn is grey and launched a season earlier; the machine that
        // reached the US was black. Both were "Model 1".
        "Saturn": [
            Variant(key: "na", label: "North America",
                    detail: "Black, 1995", asset: nil),
            Variant(key: "jp", label: "Japan",
                    detail: "Grey, 1994", asset: "variant-saturn-jp"),
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
            Variant(key: "compact", label: "Macintosh",
                    detail: "Compact, 1984", asset: "variant-mac-compact"),
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
