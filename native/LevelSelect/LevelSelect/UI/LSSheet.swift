import SwiftUI

extension View {
    /// **How every menu sheet in the app opens.**
    ///
    /// There used to be three answers. Arrange Stats opened part-way and
    /// glassy; Add Game painted its own 62% tint and went straight to full
    /// height; Settings took the platform default and went full height and
    /// gray. Tim: *"None of the other sheets only come up part way as glass,
    /// which is an inconsistency across menu sheets. They need to all open
    /// like arrange stats, or they need to all open like home's settings."*
    ///
    /// He chose Arrange Stats, and that choice is only available because of
    /// what was learned trying the alternative: **the glass is the detent, not
    /// the background.** Tested on the simulator — `.regularMaterial` and
    /// `.ultraThinMaterial` on a full-height sheet render pixel-identically
    /// flat, because iOS scales and dims the presenting view behind a `.large`
    /// sheet and leaves no material anything to sample. A partial detent is the
    /// only way to have it.
    ///
    /// `.scrolls` is what makes a partial detent somewhere you can work rather
    /// than a stop on the way to the top: without it a drag anywhere in the
    /// content raises the sheet instead of scrolling, which is how Arrange
    /// Stats' five groups were unreachable at the detent that made them glass.
    /// The sheet still resizes from its grabber and header.
    ///
    /// Not for image viewers or the system share sheet. A photo wants the whole
    /// screen, and `ShareSheet` is UIKit's own.
    func lsSheet(_ detents: Set<PresentationDetent> = [.medium, .large]) -> some View {
        #if os(macOS)
        return self
        #else
        return self
            .presentationDetents(detents)
            .presentationContentInteraction(.scrolls)
        #endif
    }
}
