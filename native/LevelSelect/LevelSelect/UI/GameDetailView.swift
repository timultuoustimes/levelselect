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
                SessionControlsView(game: game)
                Divider()
                notes
                dekuButton
            }
            .padding()
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
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

    private var notes: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Notes", systemImage: "note.text").font(.headline)
            TextField("Where you left off, thoughts, …", text: $game.notes, axis: .vertical)
                .lineLimit(3...)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var dekuButton: some View {
        Button {
            browserTarget = DekuLinkTarget(url: DekuLinks.search(for: game.name))
        } label: {
            Label("View on Deku Deals", systemImage: "tag.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(LSTheme.purple)
    }
}
