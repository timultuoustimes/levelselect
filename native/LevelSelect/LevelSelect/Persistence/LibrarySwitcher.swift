import Foundation
import SwiftData
import Observation

/// Which library the app currently has open: the real one, or the disposable
/// demo library used for screenshots and video.
///
/// The demo library is a **separate store file**, not a filtered view of the
/// real one. That matters more than it might sound:
///
/// - The real library is never touched. It isn't hidden, flagged or filtered —
///   it simply isn't open. A filtering bug can show or delete the wrong rows;
///   the worst this can do is open the wrong file.
/// - The demo store is CloudKit-free, so fake games can never sync to the
///   user's other devices or land in their iCloud needing a purge afterwards.
///   The old approach — seeding demo games *alongside* 159 real ones — is why
///   screenshots were blocked in the first place.
/// - Nothing else in the app has to learn about demo mode. Queries, views and
///   the repository all just use whatever container is current.
///
/// Which library a device is showing is deliberately stored in `UserDefaults`
/// and NOT synced. This is the rare case where device-local is correct: putting
/// one device into demo mode to take screenshots must not flip the others.
@MainActor
@Observable
final class LibrarySwitcher {
    static let shared = LibrarySwitcher()

    private static let defaultsKey = "levelselect.demoLibraryActive"

    /// True when the demo library is open.
    private(set) var isDemo: Bool

    /// True for one runloop turn while the store is being replaced.
    ///
    /// The container swap used to happen with the old view tree still on
    /// screen, and SwiftUI renders one more frame from it. A view holding a
    /// `Game` from the dead container that touches a RELATIONSHIP hits a
    /// SwiftData assertion and takes the app down — which is what happened on
    /// the Mac the moment the demo library was chosen. Showing a placeholder
    /// first means nothing is pointing at the old store when it goes.
    private(set) var isSwitching = false
    /// The container for whichever library is open. Swapping this is what
    /// switches the app over.
    private(set) var container: ModelContainer

    private init() {
        #if LEGACY_IMPORT
        let active = UserDefaults.standard.bool(forKey: Self.defaultsKey)
        #else
        // Release builds have no demo library at all, so they can never come
        // up pointed at one — even if the flag somehow survived in defaults.
        let active = false
        #endif
        isDemo = active
        container = LevelSelectStore.makeContainer(demo: active)
    }

    /// Switch libraries. No-op if already there.
    ///
    /// Rebuilding the container is the whole mechanism — the previous one is
    /// released and every view picks up the new context. Nothing is written to
    /// or read from the library being left.
    func setDemo(_ on: Bool) {
        guard on != isDemo else { return }
        // A Live Activity belongs to the library that started it. Its session
        // lives in the store we're about to close, so leaving it running
        // stranded it on the Lock Screen: the controls look live, but Stop
        // can't find the session any more and does nothing, and the only way
        // out is to swipe it away.
        LiveActivityManager.endCurrent()
        UserDefaults.standard.set(on, forKey: Self.defaultsKey)

        // Tear the tree down first, swap on the next turn.
        isSwitching = true
        Task { @MainActor in
            isDemo = on
            container = LevelSelectStore.makeContainer(demo: on)
            isSwitching = false
        }
    }

    /// Delete the demo store from disk. Only ever touches `demo.store`, so
    /// there is no path here that can reach the real library.
    func destroyDemoStore() {
        guard !isDemo else { return }
        let base = LevelSelectStore.demoStoreURL
        // SQLite keeps its write-ahead log and shared memory alongside the
        // main file; leaving those behind would resurrect the old contents.
        for suffix in ["", "-wal", "-shm"] {
            let url = URL(fileURLWithPath: base.path + suffix)
            try? FileManager.default.removeItem(at: url)
        }
    }
}
