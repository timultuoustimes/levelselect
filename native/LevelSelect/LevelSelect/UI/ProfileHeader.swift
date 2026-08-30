import SwiftUI
import SwiftData
import PhotosUI

/// The person Home belongs to.
///
/// Home is the app's one plural page — many games, several statuses, no single
/// piece of art to build it around. The audit's answer to that was shelf
/// geometry; Tim's was better: the thing uniting a plural page is **whose it
/// is**. This is that, said once at the top.
///
/// It shows only what someone actually put there. No avatar and no name means
/// no header at all, because a placeholder ring above "Add your name" is a
/// form, and a form is the opposite of a personal page.
struct ProfileHeader: View {
    let profile: PlayerProfile?
    var onEdit: () -> Void

    private var hasAnything: Bool {
        guard let profile else { return false }
        return profile.avatarData != nil
            || !(profile.displayName ?? "").isEmpty
            || !profile.handles.isEmpty
    }

    var body: some View {
        if let profile, hasAnything {
            Button(action: onEdit) {
                HStack(alignment: .center, spacing: 12) {
                    avatar(profile)

                    VStack(alignment: .leading, spacing: 4) {
                        if let name = profile.displayName, !name.isEmpty {
                            Text(name)
                                .font(.title3.bold())
                                .foregroundStyle(.primary)
                        }
                        handleRows(profile)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func avatar(_ profile: PlayerProfile) -> some View {
        if let data = profile.avatarData {
            // Uncropped and unframed. A character render with a transparent
            // background should stand in the header the way a logo stands on a
            // game page — a circular mask would cut the top off anything
            // taller than it is wide, which is most characters.
            LocalArtworkThumb(data: data, contentMode: .fit)
                .frame(width: 56, height: 56)
        } else if let initial = profile.displayName?.trimmingCharacters(in: .whitespaces).first {
            // Their letter, not a generic person glyph — the same reason the
            // empty Home gets the DoorMark rather than a controller outline.
            Text(String(initial).uppercased())
                .font(.title2.bold())
                .foregroundStyle(LSTheme.accent)
                .frame(width: 52, height: 52)
                .background(LSTheme.accent.opacity(0.16), in: .circle)
        }
    }

    /// One row per distinct handle, carrying every service that uses it.
    ///
    /// Someone using the same name on Steam, Xbox and PSN sees it once with
    /// three marks — not the same word three times. See
    /// `PlayerProfile.groupedHandles`.
    @ViewBuilder
    private func handleRows(_ profile: PlayerProfile) -> some View {
        let grouped = profile.groupedHandles
        if !grouped.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(grouped, id: \.handle) { row in
                    HStack(spacing: 5) {
                        Text(row.services.map(\.label).joined(separator: " · "))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(row.handle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

/// An image waiting to be positioned. `sheet(item:)` needs identity and `Data`
/// has none of its own.
/// The editor's one sheet, as a value.
///
/// Two `.sheet` modifiers on the same view do NOT both work — SwiftUI keeps
/// one and silently drops the other, which is why "Game art" opened nothing.
/// One modifier driven by an enum is the shape that actually works.
private enum AvatarSheet: Identifiable {
    case artwork
    case crop(Data)

    var id: String {
        switch self {
        case .artwork: "artwork"
        case .crop(let d): "crop-\(d.count)"
        }
    }
}

/// Editing the profile. Everything is optional and blank means absent — there
/// is nothing here to "complete".
struct ProfileEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [PlayerProfile]

    @State private var name = ""
    @State private var handles: [String: String] = [:]
    @State private var picking: PhotosPickerItem?
    /// Which sheet is up, if any. One modifier, one source of truth.
    @State private var sheet: AvatarSheet?
    @State private var avatar: Data?
    @State private var importError: String?

    private var profile: PlayerProfile? { profiles.first }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 10) {
                            if let avatar {
                                LocalArtworkThumb(data: avatar, contentMode: .fit)
                                    .frame(width: 108, height: 108)
                            } else {
                                Image(systemName: "person.crop.circle")
                                    .font(.system(size: 72))
                                    .foregroundStyle(.tertiary)
                            }
                            HStack(spacing: 16) {
                                PhotosPicker("Photo", selection: $picking, matching: .images)
                                Button("Game art") { sheet = .artwork }
                            }
                            .font(.subheadline)
                            if avatar != nil {
                                Button("Remove picture", role: .destructive) { avatar = nil }
                                    .font(.caption)
                            }
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                Section {
                    TextField("Your name", text: $name)
                } footer: {
                    Text("Shown at the top of Home. Leave it blank and nothing appears.")
                }

                Section {
                    ForEach(GamerService.allCases, id: \.rawValue) { service in
                        handleField(service)
                    }
                } header: {
                    Text("Handles")
                } footer: {
                    // Says the two rules rather than making anyone discover
                    // them, and says plainly that these do nothing.
                    Text("Only the ones you fill in are shown. Use the same handle on several services and it appears once, with each service beside it. These are decoration — nothing signs in and nothing is shared.")
                }

                if let importError {
                    Text(importError)
                        .font(.footnote)
                        .foregroundStyle(LSTheme.working)
                }
            }
            #if os(macOS)
            .formStyle(.grouped)
            #endif
            .navigationTitle("Your profile")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save(); dismiss() }
                }
            }
            .task { load() }
            .task(id: picking) { await ingest() }
            .sheet(item: $sheet) { which in
                switch which {
                case .artwork:
                    AvatarArtworkPicker { take($0) }
                case .crop(let raw):
                    AvatarCropView(source: raw) { take($0, alreadyCropped: true) }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 520)
        #endif
    }

    private func handleField(_ service: GamerService) -> some View {
        HStack {
            Text(service.label)
            Spacer()
            TextField("handle", text: binding(for: service))
                .multilineTextAlignment(.trailing)
                #if !os(macOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
        }
    }

    private func binding(for service: GamerService) -> Binding<String> {
        Binding(
            get: { handles[service.rawValue] ?? "" },
            set: { handles[service.rawValue] = $0 }
        )
    }

    /// The one rule that decides how an avatar behaves, applied in one place.
    ///
    /// **Transparency present** — a cut-out PNG, whether from Photos or from
    /// game art — goes straight in and is drawn whole, unframed, the way a
    /// logo sits on a game page. There is nothing to crop: the image is
    /// already the subject and nothing else.
    ///
    /// **Opaque** — a photo, or a wide painting of a whole scene — gets the
    /// positioning step, because something has to choose which square of a
    /// 16:9 image survives and the person is better at that than a centre
    /// crop. The character is rarely in the middle.
    ///
    /// Nobody is asked which of these they want. The image already knows.
    private func take(_ raw: Data, alreadyCropped: Bool = false) {
        if !alreadyCropped && !ImageIngest.hasAlpha(raw) {
            // Replacing the artwork sheet with the crop sheet, not stacking
            // one on the other.
            sheet = .crop(raw)
            return
        }
        do {
            avatar = try ImageIngest.prepareAvatar(raw).data
            importError = nil
        } catch {
            importError = "That picture couldn't be used. Try another."
        }
        sheet = nil
    }

    private func load() {
        guard let profile else { return }
        name = profile.displayName ?? ""
        handles = profile.handles
        avatar = profile.avatarData
    }

    private func ingest() async {
        guard let picking else { return }
        importError = nil
        do {
            guard let raw = try await picking.loadTransferable(type: Data.self) else { return }
            // Same downscaler the artwork picker uses. An avatar drawn at 52pt
            // has no business carrying a camera's output, and keeping it small
            // is what lets `avatarData` be a plain inline field.
            take(raw)
        } catch {
            importError = "That picture couldn't be used. Try another."
        }
    }

    private func save() {
        let target: PlayerProfile
        if let profile {
            target = profile
        } else {
            target = PlayerProfile()
            context.insert(target)
        }
        target.displayName = name.trimmingCharacters(in: .whitespaces).isEmpty ? nil : name
        target.avatarData = avatar
        target.handles = handles
        target.updatedAt = .now
        PersistenceMonitor.shared.commit(context)
    }
}
