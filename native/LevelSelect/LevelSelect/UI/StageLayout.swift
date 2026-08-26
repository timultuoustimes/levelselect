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
    /// Where the stage earns its keep. 852 is a standard iPhone's landscape
    /// width, so every iPhone from that size up — and every unfolded phone
    /// wide enough to deserve it — gets the split; smaller windows keep the
    /// single column. Tim's call, made by looking at the panes: 852 gives the
    /// tracker 358pt beside a 494pt page, which reads.
    static let minimumWidth: CGFloat = 852

    static func fits(_ size: CGSize) -> Bool {
        size.width >= minimumWidth && size.width > size.height
    }
}
