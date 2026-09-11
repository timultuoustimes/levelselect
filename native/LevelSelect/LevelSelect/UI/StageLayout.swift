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

    // MARK: Three columns

    /// **Where the page can stay beside both panels.**
    ///
    /// Stage 3 (tracker and videos) slid the game page entirely off-screen,
    /// which on an iPad in landscape was the only way to fit two panels. In a
    /// window 3840px wide it left the page gone and two panels with 1,200pt
    /// between them (Tim's 09-09 resize shots 05 and 07). From this width the
    /// page stays as the first of three columns. A 13" iPad in landscape is
    /// 1,376pt, just under it, where three columns would be cramped.
    static let threeColumnWidth: CGFloat = 1400

    /// Where each pane sits, as offsets and widths across the stage.
    struct Columns: Equatable {
        var pageWidth: CGFloat, pageX: CGFloat
        var trackerWidth: CGFloat, trackerX: CGFloat
        var videoWidth: CGFloat, videoX: CGFloat
    }

    /// The panes for a stage (1 = page, 2 = + tracker, 3 = + videos). A pane
    /// that is closed is parked just past the trailing edge, so it slides in
    /// rather than appearing.
    static func columns(width w: CGFloat, stage: Int) -> Columns {
        let three = w >= threeColumnWidth
        switch stage {
        case 1:
            return Columns(pageWidth: w, pageX: 0,
                           trackerWidth: w * 0.42, trackerX: w,
                           videoWidth: w * 0.54, videoX: w * 1.02)
        case 2:
            return Columns(pageWidth: w * 0.58, pageX: 0,
                           trackerWidth: w * 0.42, trackerX: w * 0.58,
                           videoWidth: w * 0.54, videoX: w * 1.02)
        default:
            return three
                ? Columns(pageWidth: w * 0.36, pageX: 0,
                          trackerWidth: w * 0.30, trackerX: w * 0.36,
                          videoWidth: w * 0.34, videoX: w * 0.66)
                : Columns(pageWidth: w * 0.58, pageX: -w * 0.58,
                          trackerWidth: w * 0.46, trackerX: 0,
                          videoWidth: w * 0.54, videoX: w * 0.46)
        }
    }
}
