import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    @Query(filter: #Predicate<Game> { $0.deletedAt == nil }) private var games: [Game]
    @Query(sort: \PlayerProfile.createdAt) private var profiles: [PlayerProfile]
    @Query(sort: \ThemeSettings.createdAt) private var themeSettings: [ThemeSettings]

    @State private var editingProfile = false
    /// Read here only for the word on the iCloud row. The page behind it owns
    /// the presentation; this is the answer you get without opening it.
    @State private var syncMonitor = SyncStatusMonitor.shared

    /// How many services are connected, or nothing at all when none are.
    ///
    /// A row that says "0 connected" is a row nagging you about a feature you
    /// have chosen not to use.
    private var servicesValue: String? {
        let connected = [RACredentials.isConfigured, ItchCredentials.isConfigured]
            .filter { $0 }.count
        return connected == 0 ? nil : "\(connected) connected"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // Live type rather than the baked lockup PNG: stays crisp
                    // at any size and follows the user's accent color.
                    //
                    // Pinned to one line and dropped entirely at accessibility
                    // sizes: unconstrained, it wrapped mid-word — "LevelSe /
                    // lect" across two oversized lines, which is a broken
                    // logo rather than a large one. A decorative banner is
                    // also the first thing that should give up its space when
                    // every control below it needs more.
                    if !typeSize.isAccessibilitySize {
                        Wordmark(size: 22, showsIcon: true)
                            .lineLimit(1)
                            .fixedSize()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                // The only way in. `ProfileHeader` on Home deliberately draws
                // nothing until there is something to draw — which, on its
                // own, made the profile unreachable: no header meant no way
                // to open the editor, so an empty profile could never stop
                // being empty. This row is always here, the way the account
                // card is always at the top of iOS Settings.
                Section {
                    Button { editingProfile = true } label: {
                        HStack(spacing: 12) {
                            profileAvatar
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profileTitle)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                Text(profileSubtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }

                // An index, not a scroll.
                //
                // Every row below either goes somewhere or answers its own
                // question on the way past. That second part is what keeps
                // iCloud fast to check even though it stopped being a section
                // of its own: "Synced" is on the row.
                //
                // Tim asked whether each tab should get its own settings
                // button. The answer was no — Library's Sort & View menu
                // already IS its per-tab settings, one tap from what it
                // affects — but the observation underneath was right: things
                // about YOUR GAMES were sitting among things about THE APP
                // with nothing marking the difference. Groups do that now, and
                // the two prose headings that used to do it are gone.
                Section {
                    SettingsRow(title: "iCloud", icon: "icloud",
                                value: syncMonitor.shortStatus) { ICloudSettingsPage() }
                    SettingsRow(title: "Library", icon: "books.vertical",
                                value: Format.gameCount(games.count)) { LibrarySettingsPage() }
                    SettingsRow(title: "Import & Export",
                                icon: "arrow.up.arrow.down.circle") { TransferSettingsPage() }
                    SettingsRow(title: "Services", icon: "link",
                                value: servicesValue) { ServicesSettingsPage() }
                    SettingsRow(title: "Notifications", icon: "bell.badge") {
                        NotificationSettingsPage()
                    }
                } header: {
                    Text("General")
                }

                Section {
                    SettingsRow(title: "Theme & colors", icon: "circle.lefthalf.filled",
                                value: LSAppearance(raw: themeSettings.first?.appearanceRaw).label) {
                        ThemeSettingsPage()
                    }
                    SettingsRow(title: "Statuses",
                                icon: "circle.grid.2x1.left.filled") { StatusSettingsPage() }
                    // Beside Statuses, because it is the same idea: the app's
                    // word for something, and yours if you disagree.
                    SettingsRow(title: "System names",
                                icon: "textformat") {
                        SystemNamesSettingsPage()
                    }
                    SettingsRow(title: "Game pages",
                                icon: "rectangle.topthird.inset.filled") { GamePagesSettingsPage() }
                    SettingsRow(title: "Trackers", icon: "checklist") { TrackerSettingsPage() }
                } header: {
                    Text("Appearance")
                }

                // Nothing in this group leaves the app any more.
                Section {
                    SettingsRow(title: "What's New", icon: "sparkles") {
                        WhatsNewView()
                    }
                    SettingsRow(title: "What's Coming", icon: "map") {
                        WhatsComingView()
                    }
                    SettingsRow(title: "Send feedback", icon: "paperplane") {
                        FeedbackView()
                    }
                } header: {
                    Text("News & feedback")
                } footer: {
                    Text("The first two read levelselect.app and send nothing about you — not even the anonymous install id. Feedback goes to \(Mail.feedbackAddress) from your own mail account, so the reply comes back to your inbox.")
                }

                Section {
                    ExternalSettingsRow(title: "How to use LevelSelect",
                                        icon: "questionmark.circle", url: AppLinks.help)
                    SettingsRow(title: "About LevelSelect", icon: "info.circle",
                                value: AboutSettingsPage.versionString) { AboutSettingsPage() }
                } header: {
                    Text("Help")
                }

                #if DEV_TOOLS
                Section {
                    SettingsRow(title: "Developer", icon: "hammer") {
                        DeveloperSettingsPage()
                    }
                }
                #endif

            }
            // This screen is mostly one-and-two-row sections, and the default
            // gap between them is sized for sections with more in them. At
            // this count it adds up to a scroll's worth of nothing.
            #if !os(macOS)
            .listSectionSpacing(.compact)
            #endif
            // macOS renders a bare `Form` in its old left-label style: labels
            // in a right-aligned gutter, controls crammed into what's left,
            // and every footer truncated to one line with an ellipsis. It is
            // why the Developer section at the bottom of this screen was
            // unreachable — the content did not fit and had nowhere to go.
            //
            // `.grouped` is the same style the iPhone gets: full-width rows,
            // footers that wrap, sections that read as sections.
            #if os(macOS)
            .formStyle(.grouped)
            // The app's own ground, not the system's gray. A sheet that keeps
            // the platform default reads as a different app bolted on — most
            // obvious on the Mac, where the window behind it is the purple
            // gradient and the sheet was flat gray.
            .scrollContentBackground(.hidden)
            .background(LSTheme.background)
            #endif
            .navigationTitle("Settings")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            // The bump lives on the PRESENTER's `onDismiss` now, not here.
            //
            // `.onDisappear` fires whenever this view leaves the screen — and
            // pushing a color editor onto this stack does exactly that. The
            // tab tree is keyed off `themeRevision`, so the push bumped it,
            // re-keyed the tree, destroyed the TabView and took the Settings
            // sheet with it: tapping a color row closed Settings instead of
            // opening anything. Same failure as the build-32 color picker,
            // reached by a different route. See RootView's `.sheet(onDismiss:)`.
            .sheet(isPresented: $editingProfile) { ProfileEditor().lsSheet() }
        }
        // A sheet with no size on macOS gets whatever the system guesses,
        // which was too short for a screen with eight sections — the last of
        // them could not be scrolled to at all. Sized to fit the longest
        // section, and resizable past it.
        #if os(macOS)
        .frame(minWidth: 540, idealWidth: 620, minHeight: 560, idealHeight: 780)
        #endif
    }

    private var profile: PlayerProfile? { profiles.first }

    private var profileTitle: String {
        let name = profile?.displayName ?? ""
        return name.isEmpty ? "Your profile" : name
    }

    /// Says what the row will DO, and for a filled-in profile says what is
    /// already in it — so the row is never a mystery in either state.
    private var profileSubtitle: String {
        guard let profile else { return "Add your name, picture and handles" }
        // Only ever offers what is actually still missing. Saying "add your
        // name" under someone's name is the row telling them it didn't work.
        let handles = profile.groupedHandles.count
        if handles > 0 { return handles == 1 ? "1 handle" : "\(handles) handles" }
        var missing: [String] = []
        if (profile.displayName ?? "").isEmpty { missing.append("name") }
        if profile.avatarData == nil { missing.append("picture") }
        missing.append("handles")
        return "Add your " + ListFormatter.localizedString(byJoining: missing)
    }

    /// The avatar box, scaled with the text it sits beside.
    ///
    /// A fixed 34×34 holding a `.headline`/`.title2` symbol: at AX XXXL the
    /// glyph grew straight out of its box and touched "Add your name…".
    /// `@ScaledMetric` ties the box to the type size so it grows with it
    /// instead of being overrun by it.
    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 34

    @ViewBuilder
    private var profileAvatar: some View {
        if let data = profile?.avatarData {
            LocalArtworkThumb(data: data, contentMode: .fit)
                .frame(width: avatarSize, height: avatarSize)
        } else if let initial = profile?.displayName?
            .trimmingCharacters(in: .whitespaces).first {
            Text(String(initial).uppercased())
                .font(.headline)
                .foregroundStyle(LSTheme.accent)
                .frame(width: avatarSize, height: avatarSize)
                .background(LSTheme.accent.opacity(0.16), in: .circle)
        } else {
            Image(systemName: "person.crop.circle")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: avatarSize, height: avatarSize)
        }
    }

}
