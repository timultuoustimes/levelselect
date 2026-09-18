import SwiftUI

/// Drag a Home shelf's games into your own order. See `ShelfOrder`.
struct ArrangeShelfSheet: View {
    let status: GameStatus
    let games: [Game]
    let hasOrder: Bool
    let save: ([UUID]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var order: [Game] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(order) { game in
                        HStack(spacing: 12) {
                            CoverThumb(urlString: game.displayCoverURLString,
                                       artwork: game.resolvedArtwork(.cover), name: game.name, status: game.status)
                                .frame(width: 34, height: 45)
                            Text(game.name).lineLimit(2)
                        }
                    }
                    .onMove { from, to in order.move(fromOffsets: from, toOffset: to) }
                } footer: {
                    Text("Drag to reorder. Games that join this shelf later go in front, so a game you've just started isn't buried at the end.")
                }
                if hasOrder {
                    Section {
                        Button("Automatic Order") {
                            save([])
                            dismiss()
                        }
                    } footer: {
                        Text("Pinned first, then most recently played — the order this shelf had before you arranged it.")
                    }
                }
            }
            #if os(iOS)
            .environment(\.editMode, .constant(.active))
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationTitle(status.sectionTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save(order.map(\.id))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear { if order.isEmpty { order = games } }
    }
}
