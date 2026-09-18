import SwiftUI

/// The genie, in the states the generator has.
///
/// **Placeholders.** These are the generated stand-ins from the web app's
/// `genie-set`, in the app so Tim can judge them on a device before build 39
/// goes to testers (09-17). The real character is part of the Caz commission
/// ([[LevelSelect roadmap]] §Later). To take them out: set `enabled` to false,
/// and delete the `genie-placeholder-*` image sets.
///
/// The poses follow the prompts note: working while it runs, bored when it
/// runs long, holding out a scroll with a questioning look when there's
/// something to check — never triumphant, since a generated tracker can be
/// wrong — and conceding when it fails.
enum GenieArt {
    static let enabled = true

    enum Pose: String {
        /// Hunched over a glowing orb cupped in both hands — generating.
        /// Tim, 09-17: `genie-working-v2.png` from the umigame archive — the one that matches the rest of the set.
        case working
        case appearing, scroll, conceding
    }

    static func image(_ pose: Pose) -> Image {
        let name = "genie-placeholder-\(pose.rawValue)"
        #if os(macOS)
        let exists = NSImage(named: name) != nil
        #else
        let exists = UIImage(named: name) != nil
        #endif
        return Image(exists ? name : "genie-placeholder-appearing")
    }
}

/// A genie at a size, or nothing when the art is off.
struct GenieFigure: View {
    let pose: GenieArt.Pose
    var size: CGFloat = 36

    var body: some View {
        if GenieArt.enabled {
            GenieArt.image(pose)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
}
