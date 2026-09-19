import SwiftUI

/// When a game page is wide enough to hold its tracker beside it.
///
/// This lives in one place because two screens have to agree on it: the
/// detail page decides whether to *become* the stage, and the pushed tracker
/// page decides whether to pop because the stage is about to show the same
/// tracker inline. When those two disagree you get a tracker on top of a
/// stage, or neither.
///
/// It is a function of the CONTAINER and nothing else — deliberately. The
/// rule used to also consult `horizontalSizeClass`, which updates on its own
/// schedule: during a live resize the environment and the geometry disagree
/// for a beat, so the same 1280×960 window rendered a two-pane stage on one
/// drag and a single column on the next. Same size, different layout,
/// intermittently — a race, not a rule. iOS 27's resizable windows make that
/// window of disagreement something people can actually see, by dragging
/// through it. One source of truth removes it.
enum StageLayout {
    /// Where the stage earns its keep, in the units this actually measures:
    /// **usable** width, safe areas already subtracted.
    ///
    /// That distinction cost a round trip. Tim asked for 852 — a standard
    /// iPhone's landscape width — but a phone in landscape spends ~124pt of
    /// that on the notch insets, so a 956pt Pro Max reports ~832 usable and a
    /// 852pt iPhone reports ~728. A threshold of 852 quietly excluded every
    /// phone it was chosen to include.
    ///
    /// 720 is the same intent stated in the right units: it's where the
    /// tracker pane (42% of the width) clears 300pt, which a phone in
    /// landscape manages and a phone in portrait never does.
    static let minimumWidth: CGFloat = 720

    static func fits(_ size: CGSize) -> Bool {
        #if DEBUG
        // Simulators can't be rotated from the command line, and the stage
        // only exists in landscape — so a debug default lets it be exercised
        // in portrait while testing. Never true in a shipping build.
        if UserDefaults.standard.bool(forKey: "ls.forceStage") {
            return size.width >= 400
        }
        #endif
        return size.width >= minimumWidth && size.width > size.height
    }
}
