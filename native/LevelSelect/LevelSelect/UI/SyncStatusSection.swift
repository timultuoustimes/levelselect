import SwiftUI
import CloudKit
import SwiftData

/// Settings section surfacing iCloud sync state (beta P0): Synced / Syncing /
/// iCloud unavailable (working locally) / sync issue — with sign-in guidance.
/// The data all comes from SyncStatusMonitor; this is presentation only.
struct SyncStatusSection: View {
    @State private var monitor = SyncStatusMonitor.shared
    @Query(filter: #Predicate<Session> {
        $0.playthrough == nil && $0.deletedAt == nil
    }) private var orphanedSessions: [Session]

    /// Local echo of the device name so the field edits smoothly; committed to
    /// DeviceIdentity on every change.
    @State private var deviceName = DeviceIdentity.name
    @Environment(\.modelContext) private var context

    private var repo: Repository { Repository(context) }

    var body: some View {
        Section {
            HStack(spacing: 12) {
                statusIcon
                    .font(.title3)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if monitor.state == .syncing {
                    ProgressView()
                }
            }
            .accessibilityElement(children: .combine)

            if !orphanedSessions.isEmpty {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(orphanedSessions.count) detached play \(orphanedSessions.count == 1 ? "session" : "sessions")")
                            .font(.body.weight(.medium))
                        Text("Preserved, but not included in game totals")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.link")
                        .foregroundStyle(.yellow)
                }
                .accessibilityElement(children: .combine)
            }
            // Sessions carry the name of the device that started them, so
            // history and the overlap prompts can say WHICH device rather
            // than "another device". iOS won't tell an app the name you gave
            // this device — it reports the model — so it's set here.
            // The app used to resolve two-device timer conflicts silently.
            // This is that decision, handed back — with the old behaviour
            // still available as one of the choices.
            Picker("Timers on two devices", selection: Binding(
                get: { repo.overlappingTimerPolicy },
                set: { repo.setOverlappingTimerPolicy($0) }
            )) {
                ForEach(OverlappingTimerPolicy.allCases) { policy in
                    Text(policy.label).tag(policy)
                }
            }

            LabeledContent("This device") {
                TextField(DeviceIdentity.systemDefaultName, text: $deviceName)
                    .multilineTextAlignment(.trailing)
                    #if !os(macOS)
                    .autocorrectionDisabled()
                    #endif
                    .onChange(of: deviceName) { _, newValue in
                        DeviceIdentity.name = newValue
                    }
            }
        } header: {
            Text("iCloud")
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                if !orphanedSessions.isEmpty {
                    Text("iCloud detached these records from their games. LevelSelect keeps their playtime instead of guessing where it belongs; this build cannot restore it to a game automatically.")
                }
                Text("New play sessions record which device they were started on, so your history and any timer conflicts can name it. \(OverlappingTimerPolicy(raw: nil).detail)")
                if let guidance {
                    Text(guidance)
                }
            }
        }
        .task {
            // Re-check the account whenever Settings opens — the cheapest
            // moment to notice a sign-in/sign-out since the last look.
            await monitor.refreshAccountStatus()
        }
    }

    // MARK: Presentation per state

    @ViewBuilder
    private var statusIcon: some View {
        switch monitor.state {
        case .synced:
            Image(systemName: "checkmark.icloud.fill").foregroundStyle(.green)
        case .syncing:
            Image(systemName: "arrow.triangle.2.circlepath.icloud.fill").foregroundStyle(.blue)
        case .accountUnavailable, .localFallback:
            Image(systemName: "icloud.slash.fill").foregroundStyle(.orange)
        case .error:
            Image(systemName: "exclamationmark.icloud.fill").foregroundStyle(.yellow)
        case .checking:
            Image(systemName: "icloud").foregroundStyle(.secondary)
        }
    }

    private var title: String {
        switch monitor.state {
        case .synced: "Synced"
        case .syncing: "Syncing…"
        case .accountUnavailable: "iCloud unavailable"
        case .localFallback: "Working locally"
        // Rate limiting is a wait, not a fault — presenting it as "Sync
        // issue" with a raw CloudKit error read as "sync is broken" during
        // exactly the half hour it was merely queued.
        case .error: monitor.isThrottled ? "iCloud is catching up" : "Sync issue"
        case .checking: "Checking iCloud…"
        }
    }

    private var detail: String? {
        switch monitor.state {
        case .synced:
            if let at = monitor.lastSyncedAt {
                return "Last synced \(at.formatted(.relative(presentation: .named)))"
            }
            // No event seen yet this launch — the store is CloudKit-backed
            // and healthy, sync just hasn't had a reason to run.
            return "Your library syncs automatically"
        case .error:
            if monitor.isThrottled {
                if let at = monitor.lastRelevantSyncAt {
                    return "Last synced \(at.formatted(.relative(presentation: .named))) — retrying automatically"
                }
                return "Retrying automatically"
            }
            if case .error(let message) = monitor.state { return message }
            return nil
        case .accountUnavailable:
            return "Changes are saved on this device"
        case .localFallback:
            return "Changes are saved on this device"
        default:
            return nil
        }
    }

    private var guidance: String? {
        switch monitor.state {
        case .accountUnavailable:
            return "Sign in to iCloud in Settings and turn on iCloud Drive for LevelSelect to sync your library across devices. Everything you add now stays safe on this device and syncs once you sign in."
        case .localFallback:
            return "iCloud couldn't start, so LevelSelect is using local storage this launch. Your data is safe on this device; relaunch the app to try iCloud again."
        case .error:
            if monitor.isThrottled {
                return "iCloud is temporarily limiting how often this device can sync — it happens after a burst of heavy activity. Nothing is lost: your changes are safe here and will sync on their own, usually within the hour. Giving the app a rest helps."
            }
            return "Sync will retry automatically. Your changes are safe on this device in the meantime."
        default:
            return nil
        }
    }
}
