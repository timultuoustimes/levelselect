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
        // **A Mac sheet has no detents, so it takes the size of its content —
        // and a Form's content has no opinion about width.**
        //
        // This branch returned `self`, which is why the Settings sheet once
        // truncated every footer: a footer is one long line, the sheet sized
        // itself to whatever the widest ROW wanted, and the prose was cut off.
        // Two screens set their own minimum afterwards and nothing else did.
        // Here it reaches every sheet at once, and a screen that wants
        // something different still sets its own frame inside — the outer
        // minimum is a floor, not a cage.
        //
        // 520 is the width at which the app's longest footers wrap to two
        // lines rather than three; the ideal is wider so a Mac sheet opens
        // looking like a Mac window rather than a phone screen on a desk.
        return frame(minWidth: 520, idealWidth: 600,
                     minHeight: 480, idealHeight: 640)
        #else
        return self
            .presentationDetents(detents)
            .presentationContentInteraction(.scrolls)
        #endif
    }
}

extension View {
    /// **A Form on a sheet, styled the way the Mac needs and the phone already
    /// is.**
    ///
    /// Left alone, macOS renders a `Form` in its old columnar style: labels
    /// right-aligned into a narrow left column, controls crowded into the
    /// right, footers truncated. It reads as a different app bolted on.
    /// `.grouped` is the same shape the iPhone gets — full-width rows, footers
    /// that wrap, sections that read as sections — and it is what
    /// `SettingsView` and `SettingsIndex` reached for one at a time.
    ///
    /// **Guarded, deliberately.** On iOS a `Form` inside a `NavigationStack`
    /// is already inset-grouped, and asking for `.grouped` there risks
    /// flattening the inset cards on a platform this is not trying to change.
    func lsFormStyle() -> some View {
        #if os(macOS)
        return formStyle(.grouped)
        #else
        return self
        #endif
    }
}

extension View {
    /// **A `DisclosureGroup`'s label, made to fill its row.**
    ///
    /// In a macOS `.grouped` Form a DisclosureGroup sizes its label to the
    /// text and draws the triangle beside it, so the whole control hugs its
    /// words and sits LEFT of the rounded card every other row lives in —
    /// "Rating labels" started 12pt outside the card and was 107pt wide where
    /// its neighbours were 480. It reads as a stray control dropped on the
    /// sheet rather than a row of the section.
    ///
    /// Filling the width puts it back in the row. `contentShape` is what makes
    /// the new empty space clickable rather than merely occupied — without it
    /// the triangle stays the only target and the row gets wider without
    /// getting easier to hit.
    func lsDisclosureLabel() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
    }
}
