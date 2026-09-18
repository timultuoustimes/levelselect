import SwiftUI

/// The waiting state for AI tracker generation.
///
/// Generation takes roughly a minute, which is a long time to stare at a 16pt
/// spinner wondering whether anything is happening. This does three things a
/// bare `ProgressView` can't: it shows **elapsed time**, so the wait is
/// legible rather than open-ended; it names the **stage** the server is
/// actually working through; and it gives the whole thing a torch-lit look
/// that belongs to this app rather than to UIKit.
///
/// Honesty note: the server doesn't stream progress, so the stage captions are
/// time-based, not literal telemetry. They're worded as what the request is
/// *for* ("Reading guides") rather than claiming live status. The stated time
/// range is deliberately the **real** one — a big game like Sonic Mania can run
/// past two minutes, so promising "about a minute" set people up to think it
/// had hung when it hadn't.
///
/// It also has to say *stay in the app*: generation runs on a normal
/// `URLSession`, which iOS suspends on backgrounding, so leaving really does
/// lose the work. Better to say so plainly than to let it fail silently.
struct GeneratingTrackerView: View {
    let startedAt: Date
    var kind: GenerationKind = .full
    /// Set during Generate All Planned: which planned list of how many.
    var batch: PlannedBatchProgress? = nil
    var onCancel: (() -> Void)?

    /// Roughly tracks what the backend does: search for a guide, read it,
    /// then structure the result. Stretched to match real timings (some games
    /// take 2+ minutes) so it doesn't sit on a stale caption for a full minute.
    private static let fullStages: [(after: TimeInterval, label: String)] = [
        (0,   "Looking for a good guide…"),
        (20,  "Reading the guide…"),
        (45,  "Finding bosses and collectibles…"),
        (80,  "Sorting them into categories…"),
        (110, "Big game — this one takes a while…"),
    ]

    /// A plan searches nothing and generates nothing, so it must not claim to.
    /// It is one short question with a short answer, and it usually beats the
    /// first caption change of a full run.
    private static let planStages: [(after: TimeInterval, label: String)] = [
        (0,  "Working out the shape of this game…"),
        (12, "Naming the categories…"),
        (30, "Nearly there…"),
    ]

    private var stages: [(after: TimeInterval, label: String)] {
        switch kind {
        case .full:     Self.fullStages
        case .plan:     Self.planStages
        case .category(_, let name): [
            (0,  "Looking for a guide to \(name)…"),
            (20, "Reading up on \(name)…"),
            (50, "Listing them out…"),
            (90, "Long list — still going…"),
        ]
        // A refresh of your own lists. It used to show the whole-game captions
        // ("Finding bosses and collectibles… Sorting them into categories"),
        // which describe work a refresh doesn't do.
        case .refresh(let names): [
            (0,   "Looking for a good guide…"),
            (20,  names.count <= 2
                ? "Updating \(names.joined(separator: " and "))…"
                : "Updating your \(names.count) lists…"),
            (60,  "Checking for anything missing…"),
            (100, "Long lists — still going…"),
        ]
        }
    }

    private var subtitle: String {
        // A batch is many one-category fills in a row. "Quicker than a full
        // tracker" would be true of each and misleading about the whole.
        if let batch {
            return "List \(min(batch.done + 1, batch.total)) of \(batch.total). Each is generated on its own, so a long plan takes a few minutes."
        }
        switch kind {
        case .full:     return "Usually 1–2 minutes. Big games can take longer."
        case .plan:     return "Just the categories — this part is quick."
        case .category: return "One list only, so this is quicker than a full tracker."
        case .refresh:  return "Only the lists you have — no new categories."
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(startedAt))
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    torch(elapsed: elapsed)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(stage(at: elapsed))
                            .font(.subheadline.weight(.medium))
                            .contentTransition(.opacity)
                            .animation(.easeInOut(duration: 0.35), value: stage(at: elapsed))
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 4)

                    Text(elapsedText(elapsed))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("\(Int(elapsed)) seconds elapsed")
                }

                shimmerBar(elapsed: elapsed)

                // The one thing the user genuinely has to know: switching apps
                // suspends the request and loses the work. Moving around inside
                // LevelSelect is fine — that's what the store made safe — so
                // say exactly which one costs you the generation.
                Label {
                    Text("Keep LevelSelect open. You can browse other screens, but leaving the app cancels this.")
                } icon: {
                    Image(systemName: "exclamationmark.circle.fill")
                }
                .font(.caption)
                .foregroundStyle(LSTheme.working)

                if let onCancel {
                    Button("Stop", role: .cancel, action: onCancel)
                        .font(.caption)
                        .buttonStyle(.borderless)
                }
            }
            .lsCard()
            .accessibilityElement(children: .combine)
        }
    }

    /// A torch that breathes. Two offset pulses so the glow and the flame
    /// don't move in lockstep, which reads as alive rather than as a loop.
    @ViewBuilder
    private func torch(elapsed: TimeInterval) -> some View {
        if GenieArt.enabled {
            // The genie at work over its orb for the whole wait (Tim, 09-17). A
            // slow float rather than the torch's pulse: a character breathes.
            let float = sin(elapsed * 1.6) * 2.5
            GenieFigure(pose: .working, size: 52)
                .offset(y: float)
                .shadow(color: LSTheme.working.opacity(0.35), radius: 6)
                .frame(width: 52, height: 52)
        } else {
            flame(elapsed: elapsed)
        }
    }

    private func flame(elapsed: TimeInterval) -> some View {
        let pulse = (sin(elapsed * 2.2) + 1) / 2          // 0…1
        let slow  = (sin(elapsed * 1.3 + 0.8) + 1) / 2
        return Image(systemName: "sparkles")
            .font(.system(size: 22))
            .foregroundStyle(LSTheme.working)
            .shadow(color: LSTheme.working.opacity(0.35 + 0.35 * pulse),
                    radius: 8 + 6 * pulse)
            .scaleEffect(0.94 + 0.10 * slow)
            .frame(width: 34, height: 34)
    }

    /// Indeterminate sweep — no fake percentage, since the server never tells
    /// us one. It only communicates "still running".
    private func shimmerBar(elapsed: TimeInterval) -> some View {
        GeometryReader { geo in
            let width = geo.size.width
            let travel = (elapsed.truncatingRemainder(dividingBy: 1.6)) / 1.6
            let bandWidth = width * 0.4
            Capsule()
                .fill(.white.opacity(0.07))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [LSTheme.working.opacity(0),
                                         LSTheme.working.opacity(0.85),
                                         LSTheme.working.opacity(0)],
                                startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(width: bandWidth)
                        .offset(x: travel * (width + bandWidth) - bandWidth)
                }
                .clipShape(Capsule())
        }
        .frame(height: 4)
    }

    private func stage(at elapsed: TimeInterval) -> String {
        stages.last { elapsed >= $0.after }?.label ?? stages[0].label
    }

    private func elapsedText(_ elapsed: TimeInterval) -> String {
        let total = Int(elapsed)
        return total < 60 ? "\(total)s" : String(format: "%d:%02d", total / 60, total % 60)
    }
}

#Preview {
    VStack(spacing: 16) {
        GeneratingTrackerView(startedAt: .now) {}
        GeneratingTrackerView(startedAt: .now.addingTimeInterval(-14), kind: .plan) {}
        GeneratingTrackerView(startedAt: .now.addingTimeInterval(-38),
                              kind: .category(id: "shrines", name: "Shrines")) {}
        GeneratingTrackerView(startedAt: .now.addingTimeInterval(-92)) {}
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(LSTheme.liveGround)
}
