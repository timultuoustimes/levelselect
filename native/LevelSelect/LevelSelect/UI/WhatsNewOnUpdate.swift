import SwiftUI

/// Shown once, the first launch after an update.
///
/// Nobody opens Settings to find out what changed, which is the whole problem
/// with a What's New that only lives behind a row. Gamery shows theirs; so
/// does every app that expects anyone to notice the work.
///
/// Three rules keep it from being an interruption:
///
/// - **Never on a fresh install.** With nothing stored, the build is recorded
///   silently. Someone who has had the app for four minutes has no "new".
/// - **Never twice for the same build**, and never for a downgrade — the
///   stored build is the high-water mark, not the last one seen.
/// - **Never before there is something to say.** It presents only after the
///   feed has been read and actually contains an entry for this build, so a
///   release whose notes have not been published yet stays quiet rather than
///   opening an empty sheet.
struct WhatsNewOnUpdate: ViewModifier {
    /// The highest build this device has already been shown notes for. 0 on a
    /// fresh install, which is the case that stays silent.
    @AppStorage("lastSeenWhatsNewBuild") private var lastSeenBuild = 0
    @State private var showing = false

    /// Read from the bundle rather than passed in — the app has exactly one
    /// answer to "which build am I".
    static var currentBuild: Int {
        Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0
    }

    func body(content: Content) -> some View {
        content
            .task { await evaluate() }
            .sheet(isPresented: $showing) {
                NavigationStack {
                    WhatsNewView(highlighting: Self.currentBuild)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showing = false }
                            }
                        }
                }
                .lsSheet([.large])
            }
    }

    private func evaluate() async {
        let build = Self.currentBuild
        guard build > 0, build > lastSeenBuild else { return }

        // A fresh install records where it came in and says nothing.
        guard lastSeenBuild > 0 else {
            lastSeenBuild = build
            return
        }

        // Only if there is something written about this build. A cached feed
        // counts — the notes for a build you already installed were published
        // before it, so an offline first launch still gets them.
        let feed = await NewsFeeds.changelog()
        guard let releases = feed.value?.releases,
              releases.contains(where: { $0.build == build }) else { return }

        lastSeenBuild = build
        showing = true
    }
}

extension View {
    func whatsNewOnUpdate() -> some View { modifier(WhatsNewOnUpdate()) }
}
