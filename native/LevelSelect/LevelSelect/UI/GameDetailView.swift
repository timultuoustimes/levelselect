import SwiftUI
import SwiftData

struct GameDetailView: View {
    @Bindable var game: Game
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false
    @State private var browserTarget: DekuLinkTarget?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero
                Divider()
                CollapsibleSection("Sessions", icon: "stopwatch") {
                    SessionControlsView(game: game)
                }
                Divider()
                CollapsibleSection("Tracker", icon: "checklist") {
                    TrackerSectionView(game: game)
                }
                Divider()
                if let summary = game.summary, !summary.isEmpty {
                    CollapsibleSection("About", icon: "text.alignleft", defaultExpanded: false) {
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Divider()
                }
                CollapsibleSection("Game Info", icon: "info.circle", defaultExpanded: false) {
                    gameInfo
                }
                Divider()
                CollapsibleSection("Tags", icon: "tag", defaultExpanded: false) {
                    tagsEditor
                }
                Divider()
                CollapsibleSection("Review", icon: "star.bubble", defaultExpanded: false) {
                    reviewEditor
                }
                Divider()
                CollapsibleSection("Notes", icon: "note.text") {
                    notesField
                }
            }
            .padding()
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background { ambientBackdrop }
        .dekuBrowser(target: $browserTarget)
        .navigationTitle(game.name)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        game.pinned.toggle()
                    } label: {
                        Label(game.pinned ? "Unpin" : "Pin", systemImage: game.pinned ? "pin.slash" : "pin")
                    }
                    Menu("Status") {
                        ForEach(GameStatus.allCases, id: \.self) { s in
                            Button {
                                game.status = s
                            } label: {
                                Label(s.label, systemImage: game.status == s ? "checkmark" : s.systemImage)
                            }
                        }
                    }
                    Divider()
                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog("Delete \(game.name)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Repository(context).softDelete(game)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Moves it to trash (recoverable).")
        }
    }

    // MARK: Backdrop

    /// Ambient page background: the game's own cover, blurred and saturated,
    /// glowing behind the top of the page and fading into the app gradient —
    /// every game gets its own atmosphere.
    private var ambientBackdrop: some View {
        ZStack(alignment: .top) {
            LSTheme.background

            if ThemePalette.pageBackground == .status {
                // Status-color gradient variant (user-selectable in Appearance).
                LinearGradient(
                    colors: [game.status.color.opacity(0.45), .clear],
                    startPoint: .top, endPoint: .center
                )
                .frame(height: 420)
                .frame(maxWidth: .infinity)
            } else if let s = game.coverURLString, let url = URL(string: s) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(height: 420)
                            .frame(maxWidth: .infinity)
                            .clipped()
                            .blur(radius: 60, opaque: true)
                            .saturation(1.5)
                            .opacity(0.55)
                            .mask(
                                LinearGradient(
                                    stops: [
                                        .init(color: .black, location: 0),
                                        .init(color: .black.opacity(0.6), location: 0.55),
                                        .init(color: .clear, location: 1),
                                    ],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                    }
                }
                .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
    }

    // MARK: Sections

    private var hero: some View {
        HStack(alignment: .top, spacing: 16) {
            CoverThumb(urlString: game.coverURLString)
                .frame(width: 110, height: 146)
                .shadow(radius: 4, y: 2)

            VStack(alignment: .leading, spacing: 8) {
                Text(game.name)
                    .font(.title2.bold())

                HStack(spacing: 6) {
                    Image(systemName: game.status.systemImage)
                        .foregroundStyle(game.status.color)
                    Text(game.status.label)
                    if let platform = game.platforms.first {
                        Text("· \(platform)").foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)

                ratingStars

                if let franchise = game.franchise, !franchise.isEmpty {
                    Text(franchise)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var ratingStars: some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: (game.rating ?? 0) >= i ? "star.fill" : "star")
                    .foregroundStyle(.yellow)
                    .onTapGesture {
                        game.rating = (game.rating == i) ? nil : i
                    }
            }
        }
        .font(.subheadline)
    }

    private var notesField: some View {
        TextField("Where you left off, thoughts, …", text: $game.notes, axis: .vertical)
            .lineLimit(3...)
            .textFieldStyle(.roundedBorder)
    }

    // MARK: Game Info

    @State private var editingInfo = false

    private var gameInfo: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        editingInfo.toggle()
                    }
                } label: {
                    Label(editingInfo ? "Done" : "Edit",
                          systemImage: editingInfo ? "checkmark" : "pencil")
                        .font(.subheadline)
                }
                .buttonStyle(.borderless)
                .tint(LSTheme.accent)
            }

            if editingInfo {
                editForm
            } else {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                    GridRow {
                        infoCell("Released", game.firstReleaseDate.map {
                            String(Calendar.current.component(.year, from: $0))
                        })
                        infoCell("Series", game.franchise)
                    }
                    GridRow {
                        infoCell("Developer", game.developers.first)
                        infoCell("Publisher", game.publishers.first)
                    }
                }

                if !game.platforms.isEmpty {
                    chipGroup("Platforms", game.platforms, tint: .blue)
                }
                let genreTheme = game.genres + game.themes
                if !genreTheme.isEmpty {
                    chipGroup("Genre / Theme", genreTheme, tint: LSTheme.accent)
                }
                if !game.gameModes.isEmpty {
                    chipGroup("Game Modes", game.gameModes, tint: .teal)
                }
                if !game.playerPerspectives.isEmpty {
                    chipGroup("Perspective", game.playerPerspectives, tint: .gray)
                }
            }

            HStack(spacing: 18) {
                Button {
                    browserTarget = DekuLinkTarget(url: DekuLinks.search(for: game.name))
                } label: {
                    Label("Deku Deals", systemImage: "tag.fill")
                }
                if let slug = game.igdbSlug,
                   let url = URL(string: "https://www.igdb.com/games/\(slug)") {
                    Button {
                        browserTarget = DekuLinkTarget(url: url)
                    } label: {
                        Label("IGDB", systemImage: "arrow.up.right.square")
                    }
                }
            }
            .font(.subheadline)
            .buttonStyle(.borderless)
            .tint(LSTheme.accent)
        }
    }

    /// Edit mode: everything IGDB filled in is overridable per game.
    private var editForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                labeledField("Released", text: Binding(
                    get: {
                        game.firstReleaseDate.map {
                            String(Calendar.current.component(.year, from: $0))
                        } ?? ""
                    },
                    set: { text in
                        if let year = Int(text), (1950..<3000).contains(year) {
                            game.firstReleaseDate = DateComponents(
                                calendar: .current, year: year, month: 1, day: 1).date
                        } else if text.isEmpty {
                            game.firstReleaseDate = nil
                        }
                    }
                ))
                labeledField("Series", text: Binding(
                    get: { game.franchise ?? "" },
                    set: { game.franchise = $0.isEmpty ? nil : $0 }
                ))
            }
            HStack(spacing: 12) {
                labeledField("Developer", text: firstElementBinding(\.developers))
                labeledField("Publisher", text: firstElementBinding(\.publishers))
            }
            EditableChips(title: "Platforms", values: $game.platforms, tint: .blue)
            EditableChips(title: "Genres", values: $game.genres, tint: LSTheme.accent)
            EditableChips(title: "Themes", values: $game.themes, tint: LSTheme.accent)
            EditableChips(title: "Game Modes", values: $game.gameModes, tint: .teal)
            EditableChips(title: "Perspective", values: $game.playerPerspectives, tint: .gray)
        }
    }

    private func labeledField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.subheadline)
        }
    }

    private func firstElementBinding(_ keyPath: ReferenceWritableKeyPath<Game, [String]>) -> Binding<String> {
        Binding(
            get: { game[keyPath: keyPath].first ?? "" },
            set: { value in
                var array = game[keyPath: keyPath]
                if value.isEmpty {
                    if !array.isEmpty { array.removeFirst() }
                } else if array.isEmpty {
                    array = [value]
                } else {
                    array[0] = value
                }
                game[keyPath: keyPath] = array
            }
        )
    }

    private func infoCell(_ label: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value?.isEmpty == false ? value! : "—").font(.subheadline)
        }
        .gridColumnAlignment(.leading)
    }

    private func chipGroup(_ label: String, _ values: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            FlowLayout(spacing: 6) {
                ForEach(values, id: \.self) { Chip(text: $0, tint: tint) }
            }
        }
    }

    // MARK: Tags

    @State private var newTag = ""

    private var tagsEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !game.userTags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(game.userTags, id: \.self) { tag in
                        Chip(text: "#\(tag)", tint: LSTheme.accent) {
                            game.userTags.removeAll { $0 == tag }
                        }
                    }
                }
            }
            TextField("Add a tag…", text: $newTag)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    let tag = newTag
                        .trimmingCharacters(in: .whitespaces)
                        .replacingOccurrences(of: "#", with: "")
                    if !tag.isEmpty, !game.userTags.contains(tag) {
                        game.userTags.append(tag)
                    }
                    newTag = ""
                }
        }
    }

    // MARK: Review

    private var reviewEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            ratingStars
            TextField("Your review…", text: Binding(
                get: { game.review ?? "" },
                set: { game.review = $0.isEmpty ? nil : $0 }
            ), axis: .vertical)
            .lineLimit(3...)
            .textFieldStyle(.roundedBorder)
        }
    }
}
