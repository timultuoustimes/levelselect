#if LEGACY_IMPORT   // developer-only, same gate as the legacy import
import Foundation
import SwiftData
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Forces the CloudKit **Development** schema to contain every record type and
/// every field in Schema V1, so `Deploy Schema Changes` promotes a COMPLETE
/// schema to Production.
///
/// Why this is needed: CloudKit derives the Development schema from records
/// actually written. A field materializes only once some record carries a
/// non-nil value for it, and a record type only once an instance syncs. Real
/// libraries leave gaps — a never-used `Profile`, no `Run` yet, `review` still
/// nil on every game — and **a field missing from Production silently fails to
/// sync for users**. Seeding writes one fully-populated instance of all 14
/// models with every optional set, closing every gap at once.
///
/// Usage (Settings → Developer, Debug builds only):
///   1. Seed, 2. wait for sync (Settings → iCloud shows Synced; confirm the
///   types appear in CloudKit Console → Development), 3. Deploy Schema
///   Changes to Production, 4. Purge.
///
/// Seed rows carry `deletedAt` and a marker name so the app's own queries
/// (all of which filter `deletedAt == nil`) never show them.
@MainActor
enum CloudKitSchemaSeeder {
    /// Marker used for both `legacyID` and display names, so purge is exact.
    static let marker = "__ls_schema_seed__"

    /// Accent written onto a theme row that had none, so CloudKit materializes
    /// the field. Reverted by purge() unless the user has since changed it.
    static let seededAccent = "#8A5CF6"

    /// A DELIBERATELY LARGE image, for seeding `GameImage.data`.
    ///
    /// Size is the entire point, and getting it wrong cost a promote.
    ///
    /// `@Attribute(.externalStorage)` does not make Core Data store every
    /// value externally — it stores values externally **above a size
    /// threshold** (~100KB). CloudKit then derives the field's type from what
    /// it actually observes: an inline value materializes as **BYTES**, an
    /// externally-stored one as an **ASSET**. Seeded with a 1x1 PNG (70
    /// bytes), `CD_GameImage.data` came through as BYTES — which caps the
    /// whole record at CloudKit's ~1MB limit and inlines every photo into the
    /// record instead of streaming it. Real images routinely exceed that, so
    /// they would have failed to sync, silently and permanently.
    ///
    /// CloudKit will not retype an existing field, so fixing it meant
    /// resetting the Development environment. Hence: seed something big
    /// enough that external storage is certain to engage.
    ///
    /// Generated rather than embedded as a base64 literal, because a
    /// multi-megabyte constant in source is its own problem. Noise, not a
    /// gradient — a smooth image compresses back under the threshold and
    /// puts us right back where we started.
    static var largeSeedImage: Data {
        let side = 900
        let bytesPerPixel = 4
        var pixels = [UInt8](repeating: 0, count: side * side * bytesPerPixel)
        // Deterministic, high-entropy fill: a cheap LCG, so the PNG can't be
        // compressed away and the seed is identical on every run.
        var state: UInt64 = 0x9E3779B97F4A7C15
        for index in pixels.indices {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            pixels[index] = UInt8truncating(state >> 33)
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let image = CGImage(
            width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: side * bytesPerPixel,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent)!

        let out = NSMutableData()
        let destination = CGImageDestinationCreateWithData(
            out, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return out as Data
    }

    /// `UInt8(truncatingIfNeeded:)` spelled as a function so the fill loop
    /// above stays readable.
    private static func UInt8truncating(_ value: UInt64) -> UInt8 {
        UInt8(truncatingIfNeeded: value)
    }

    /// A DELIBERATELY TINY image — the other half of the pair.
    ///
    /// Core Data keeps a small binary value inline rather than moving it to
    /// external storage, and CloudKit then mirrors it as `CD_data` (BYTES)
    /// instead of `CD_data_ckAsset` (ASSET). Real logos land here: a
    /// wordmark PNG is a few tens of KB, and Tim's was 121KB and still
    /// inline. Without this row, Production has no BYTES field and every
    /// small image fails to sync forever.
    ///
    /// 8x8 flat colour, a few hundred bytes — far below any plausible
    /// threshold, in the way `largeSeedImage` is far above one. The point of
    /// both is to be unambiguous.
    static var smallSeedImage: Data {
        let side = 8
        let bytesPerPixel = 4
        var pixels = [UInt8](repeating: 0, count: side * side * bytesPerPixel)
        for index in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
            pixels[index] = 0x8A       // R
            pixels[index + 1] = 0x5C   // G
            pixels[index + 2] = 0xFA   // B
            pixels[index + 3] = 0xFF   // A
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let image = CGImage(
            width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: side * bytesPerPixel,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent)!

        let out = NSMutableData()
        let destination = CGImageDestinationCreateWithData(
            out, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return out as Data
    }

    /// Insert one fully-populated instance of every model in SchemaV1.
    /// Returns a short report for the UI.
    @discardableResult
    static func seed(context: ModelContext) -> String {
        let now = Date.now
        let stamp = Data("{}".utf8)

        // --- Root: Game, with every optional populated ---
        let game = Game(name: marker)
        game.userID = UUID()
        game.deletedAt = now          // invisible to every app query
        game.legacyID = marker
        game.name = marker
        game.summary = marker
        game.notes = marker
        game.igdbID = 1
        game.igdbSlug = marker
        game.firstReleaseDate = now
        game.franchise = marker
        game.coverURLString = marker
        game.coverImageID = marker
        game.coverOverrideURLString = marker    // V2
        game.logoURLString = marker            // V3
        game.backdropURLString = marker        // V3
        game.status = .playing
        game.pinned = true
        game.rating = 5
        game.review = marker
        game.addedAt = now
        game.currentPlaythroughID = UUID()
        game.trackerDisplayRaw = TrackerDisplay.inline.rawValue
        game.showItemHintsOverride = true
        game.platforms = [marker]
        game.ownership = [Ownership.physical.rawValue]
        game.userTags = [marker]
        game.genres = [marker]
        game.themes = [marker]
        game.gameModes = [marker]
        game.playerPerspectives = [marker]
        game.developers = [marker]
        game.publishers = [marker]
        context.insert(game)

        // --- Playthrough ---
        let pt = Playthrough(name: marker)
        pt.userID = UUID()
        pt.deletedAt = now
        pt.legacyID = marker
        pt.name = marker
        pt.notes = marker
        pt.progressPercent = 50
        pt.outcomeRaw = PlaythroughOutcome.shelved.rawValue
        pt.outcomeNote = marker
        pt.startedAt = now
        pt.lastPlayedAt = now
        context.insert(pt)
        pt.game = game

        // --- Session ---
        let session = Session(startDate: now, state: .stopped, isManual: true)
        session.userID = UUID()
        session.deletedAt = now
        session.legacyID = marker
        session.startDate = now
        session.endDate = now
        session.accumulatedDuration = 60
        session.companions = [Companion(name: marker, handle: marker)]
        session.resumedAt = now
        session.pausedAt = now
        session.state = .stopped
        session.isManual = true
        session.notes = marker
        session.originDevice = marker          // V2
        context.insert(session)
        session.playthrough = pt

        // --- Run ---
        let run = Run(templateID: marker, startedAt: now, outcome: .success, fieldsJSON: stamp)
        run.userID = UUID()
        run.deletedAt = now
        run.legacyID = marker
        run.templateID = marker
        run.startedAt = now
        run.endedAt = now
        run.outcome = .success
        run.fieldsJSON = stamp
        run.notes = marker
        run.companions = [Companion(name: marker, handle: marker)]
        context.insert(run)
        run.playthrough = pt

        // --- TrackerStateRecord (count/rank/notes are the usual gaps) ---
        let state = TrackerStateRecord(itemID: marker, completed: true, count: 1, rank: 1, revealed: true)
        state.userID = UUID()
        state.deletedAt = now
        state.legacyID = marker
        state.itemID = marker
        state.completed = true
        state.completedAt = now
        state.count = 1
        state.rank = 1
        state.revealed = true
        state.notes = marker
        state.selectedVariant = marker         // V2
        context.insert(state)
        state.playthrough = pt

        // --- TrackerSchemaRecord ---
        let schema = TrackerSchemaRecord(schemaVersion: 1, source: .aiGenerated, engine: .run, jsonData: stamp)
        schema.userID = UUID()
        schema.deletedAt = now
        schema.legacyID = marker
        schema.schemaVersion = 1
        schema.source = .aiGenerated
        schema.engine = .run
        schema.generatedAt = now
        schema.generatedBy = marker
        schema.jsonData = stamp
        schema.sourcesJSON = stamp
        context.insert(schema)
        schema.game = game

        // --- CompletionEvent ---
        let completion = CompletionEvent(date: now, label: .custom)
        completion.userID = UUID()
        completion.deletedAt = now
        completion.legacyID = marker
        completion.date = now
        completion.label = .custom
        completion.customLabel = marker
        completion.platform = marker
        completion.notes = marker
        completion.datePrecision = "year"
        completion.startedDate = now
        completion.startedPrecision = "year"
        completion.companions = [Companion(name: marker, handle: marker)]
        context.insert(completion)
        completion.game = game
        completion.playthrough = pt

        // --- GameVideo ---
        let video = GameVideo(kind: .playlist, urlString: marker, youtubeID: marker, title: marker)
        video.userID = UUID()
        video.deletedAt = now
        video.legacyID = marker
        video.kindRaw = VideoKind.playlist.rawValue
        video.urlString = marker
        video.youtubeID = marker
        video.title = marker
        video.channel = marker
        video.thumbnailURL = marker
        video.groupName = marker
        video.orderIndex = 1
        video.notes = marker
        video.watchedSeconds = 1
        video.watchedPartIndex = 1
        video.lastWatchedAt = now
        video.partsData = stamp
        context.insert(video)
        video.game = game

        // --- GameMap + Marker (maps are P2, but the schema must exist now:
        //     adding fields later means another Production deploy) ---
        let map = GameMap(name: marker, kind: .world, storageType: "upload", remoteStoragePath: marker, addedAt: now)
        map.userID = UUID()
        map.deletedAt = now
        map.legacyID = marker
        map.name = marker
        map.kind = .world
        map.storageType = "upload"
        map.remoteStoragePath = marker
        map.remoteURLString = marker
        map.localCacheURL = URL(string: "file:///dev/null")
        map.pixelWidth = 1
        map.pixelHeight = 1
        map.addedAt = now
        context.insert(map)
        map.game = game

        let pin = Marker(normalizedX: 0.5, normalizedY: 0.5, category: .note, label: marker)
        pin.userID = UUID()
        pin.deletedAt = now
        pin.legacyID = marker
        pin.normalizedX = 0.5
        pin.normalizedY = 0.5
        pin.category = .note
        pin.label = marker
        pin.notes = marker
        pin.linkedTrackerItemID = marker
        context.insert(pin)
        pin.map = map

        // --- TrackerItemDetail (V2: the user's own note/rename, split out of
        //     the schema blob so per-item edits merge) ---
        let itemDetail = TrackerItemDetail(itemID: marker, note: marker,
                                           chosenName: marker, sourceName: marker)
        itemDetail.userID = UUID()
        itemDetail.deletedAt = now
        itemDetail.legacyID = marker
        context.insert(itemDetail)
        itemDetail.game = game

        // --- EarnedBadge (V2: ships before the feature that awards them —
        //     the schema still has to exist in Production first) ---
        let badge = EarnedBadge(badgeID: marker, earnedAt: now,
                                gameID: game.id, detailJSON: stamp)
        badge.userID = UUID()
        badge.deletedAt = now
        badge.legacyID = marker
        context.insert(badge)

        // --- GameImage (V3) — TWO of them, and the pair is the whole point ---
        //
        // `@Attribute(.externalStorage)` does not choose one CloudKit field.
        // It chooses PER VALUE, by size: Core Data keeps a small blob inline
        // and moves a large one to external storage, and the CloudKit mirror
        // names them differently — `CD_data` (BYTES) versus
        // `CD_data_ckAsset` (ASSET). Both are ordinary outputs of this app,
        // so PRODUCTION MUST CONTAIN BOTH FIELDS.
        //
        // Seeding only a large image (the first fix, which corrected a real
        // ASSET problem) left the BYTES field missing — and logos are exactly
        // the small case, because wordmark PNGs compress tiny. Tim's 121KB
        // Skate Story logo stayed inline, CloudKit reached for a `CD_data`
        // that Production didn't have, and every sync failed with
        // CKErrorDomain error 2, permanently and silently. Verified by
        // pulling the store off the device: `length(ZDATA) = 121056` in the
        // row, `_EXTERNAL_DATA` empty.
        //
        // So: one image comfortably OVER the threshold and one comfortably
        // UNDER it. Never reduce this to a single row.
        let largeBytes = Self.largeSeedImage
        let largeImage = GameImage(role: .gallery, data: largeBytes)
        largeImage.userID = UUID()
        largeImage.deletedAt = now
        largeImage.legacyID = marker
        largeImage.caption = marker
        largeImage.roleRaw = ArtworkRole.gallery.rawValue
        largeImage.pixelWidth = 900
        largeImage.pixelHeight = 900
        largeImage.byteCount = largeBytes.count
        largeImage.addedAt = now
        context.insert(largeImage)
        largeImage.game = game

        let smallBytes = Self.smallSeedImage
        let smallImage = GameImage(role: .logo, data: smallBytes)
        smallImage.userID = UUID()
        smallImage.deletedAt = now
        smallImage.legacyID = marker
        smallImage.caption = marker
        smallImage.roleRaw = ArtworkRole.logo.rawValue
        smallImage.pixelWidth = 8
        smallImage.pixelHeight = 8
        smallImage.byteCount = smallBytes.count
        smallImage.addedAt = now
        context.insert(smallImage)
        smallImage.game = game

        // --- GameCollection ---
        let collection = GameCollection(name: marker, isBundle: true, sortIndex: 1)
        collection.userID = UUID()
        collection.deletedAt = now
        collection.legacyID = marker
        collection.name = marker
        collection.notes = marker
        collection.sortIndex = 1
        collection.isBundle = true
        collection.gameIDs = [game.id.uuidString]
        context.insert(collection)

        // --- PlayerProfile (build 33; no soft-delete field, purge removes it) ---
        //
        // `avatarData` is a PLAIN Data field, not externalStorage, so one seed
        // creates it. The GameImage lesson from build 32 — externalStorage
        // picks BYTES or ASSET by size, so the schema needs both and seeding
        // needs two images straddling the threshold — does not apply, and
        // deliberately so.
        let player = PlayerProfile()
        player.displayName = marker
        player.avatarData = Self.smallSeedImage
        player.handles = [GamerService.steam.rawValue: marker]
        context.insert(player)

        // --- Profile (no soft-delete field; purge removes it) ---
        let profile = Profile(appleUserIdentifier: marker, email: marker, displayName: marker)
        profile.appleUserIdentifier = marker
        profile.email = marker
        profile.displayName = marker
        context.insert(profile)

        // --- MigrationReceipt (no soft-delete field) ---
        let receipt = MigrationReceipt(sourceDeviceID: marker, appVersion: marker, countsJSON: stamp)
        receipt.sourceDeviceID = marker
        receipt.importedAt = now
        receipt.appVersion = marker
        receipt.countsJSON = stamp
        context.insert(receipt)

        // --- ThemeSettings (singleton-ish; seed only if absent, since a real
        //     one drives the app's palette and a second would be ambiguous) ---
        let existingTheme = (try? context.fetch(FetchDescriptor<ThemeSettings>()))?.first
        if let existingTheme {
            // Populate the optionals on the REAL row instead of adding a second
            // (a duplicate would fight ThemePalette, which reads `.first`).
            // These are USER-VISIBLE settings, so purge() puts them back — a
            // seeded accent would otherwise silently become the user's choice
            // and, since the wordmark follows a custom accent, change the
            // app's look permanently.
            if existingTheme.accentHex == nil { existingTheme.accentHex = seededAccent }
            if existingTheme.statusColorsData == nil { existingTheme.statusColorsData = stamp }
            // V2 optionals. Marker values, reverted by purge() — these are
            // real preferences, and a seeded one silently becoming the user's
            // choice is the same trap as the accent.
            if existingTheme.defaultMergeModeRaw == nil { existingTheme.defaultMergeModeRaw = marker }
            if existingTheme.overlappingTimerPolicyRaw == nil { existingTheme.overlappingTimerPolicyRaw = marker }
            if existingTheme.platformIconVariantsData == nil { existingTheme.platformIconVariantsData = stamp }
            if existingTheme.dekuWishlistURLString == nil { existingTheme.dekuWishlistURLString = marker }
            if existingTheme.starNamesData == nil { existingTheme.starNamesData = stamp }
            if existingTheme.backdropIntensityRaw == nil { existingTheme.backdropIntensityRaw = marker }
            if existingTheme.gamePageLayoutRaw == nil { existingTheme.gamePageLayoutRaw = marker }
        } else {
            let theme = ThemeSettings()
            theme.accentHex = "#8A5CF6"
            theme.statusColorsData = stamp
            theme.defaultMergeModeRaw = marker           // V2
            theme.overlappingTimerPolicyRaw = marker     // V2
            theme.platformIconVariantsData = stamp       // V2
            theme.dekuWishlistURLString = marker         // V2
            theme.starNamesData = stamp                  // build 31
            theme.backdropIntensityRaw = marker           // build 32
            theme.gamePageLayoutRaw = marker              // build 33
            context.insert(theme)
        }

        PersistenceMonitor.shared.commit(context)
        return """
        Seeded 16 record types with all fields populated, including TWO         GameImages — one large, one small — so the schema carries both         CD_data (BYTES) and CD_data_ckAsset (ASSET). Wait for Settings →         iCloud to show Synced, then verify in CloudKit Console         (Development). CHECK BOTH image fields are present before deploying:         a missing one means every image of that size fails to sync forever.         Then Deploy Schema Changes to Production, and Purge.
        """
    }

    /// Hard-delete every seeded row. Schema changes are permanent once created,
    /// so purging never undoes the seeding — it only cleans up the data.
    @discardableResult
    static func purge(context: ModelContext) -> String {
        var removed = 0
        func purgeAll<T: PersistentModel>(_ type: T.Type, matches: (T) -> Bool) {
            let all = (try? context.fetch(FetchDescriptor<T>())) ?? []
            for item in all where matches(item) {
                context.delete(item)
                removed += 1
            }
        }
        purgeAll(Game.self) { $0.legacyID == marker }
        purgeAll(Playthrough.self) { $0.legacyID == marker }
        purgeAll(Session.self) { $0.legacyID == marker }
        purgeAll(Run.self) { $0.legacyID == marker }
        purgeAll(TrackerStateRecord.self) { $0.legacyID == marker }
        purgeAll(TrackerSchemaRecord.self) { $0.legacyID == marker }
        purgeAll(CompletionEvent.self) { $0.legacyID == marker }
        purgeAll(GameVideo.self) { $0.legacyID == marker }
        purgeAll(GameMap.self) { $0.legacyID == marker }
        purgeAll(Marker.self) { $0.legacyID == marker }
        purgeAll(GameCollection.self) { $0.legacyID == marker }
        purgeAll(TrackerItemDetail.self) { $0.legacyID == marker }
        purgeAll(EarnedBadge.self) { $0.legacyID == marker }
        purgeAll(GameImage.self) { $0.legacyID == marker }
        purgeAll(Profile.self) { $0.appleUserIdentifier == marker }
        purgeAll(PlayerProfile.self) { $0.displayName == marker }
        purgeAll(MigrationReceipt.self) { $0.sourceDeviceID == marker }

        // Undo the theme fields we populated, so a seeding run never leaves the
        // user with an accent (or status colors) they didn't pick.
        if let theme = (try? context.fetch(FetchDescriptor<ThemeSettings>()))?.first {
            if theme.accentHex == seededAccent {
                theme.accentHex = nil
                removed += 1
            }
            if theme.statusColorsData == Data("{}".utf8) {
                theme.statusColorsData = nil
            }
            if theme.defaultMergeModeRaw == marker { theme.defaultMergeModeRaw = nil }
            if theme.overlappingTimerPolicyRaw == marker { theme.overlappingTimerPolicyRaw = nil }
            if theme.platformIconVariantsData == Data("{}".utf8) { theme.platformIconVariantsData = nil }
            if theme.dekuWishlistURLString == marker { theme.dekuWishlistURLString = nil }
            if theme.starNamesData == Data("{}".utf8) { theme.starNamesData = nil }
            if theme.backdropIntensityRaw == marker { theme.backdropIntensityRaw = nil }
            if theme.gamePageLayoutRaw == marker { theme.gamePageLayoutRaw = nil }
            ThemePalette.refresh(from: theme)
        }

        PersistenceMonitor.shared.commit(context)
        return "Removed \(removed) seed record(s). The deployed schema is unaffected."
    }
}
#endif
