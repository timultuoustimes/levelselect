import SwiftUI
import SwiftData

/// Wishlist tab: your public Deku Deals wishlist, native. Tap a row → its
/// Deku page (price history) in the in-app browser. Long-press → Add to
/// Library (IGDB pre-searched, lands as Wishlist status). Browse button opens
/// Deku itself; the list refreshes when the browser closes.
struct WishlistTab: View {
    struct AddTarget: Identifiable {
        let name: String
        var id: String { name }
    }

    @State private var store = DekuWishlistStore()
    @State private var searchText = ""
    @State private var browserTarget: DekuLinkTarget?
    @State private var addSearch: AddTarget?

    var body: some View {
        NavigationStack {
            Group {
                if !store.isConfigured {
                    setupPrompt
                } else {
                    list
                }
            }
            .lsBackground()
            .navigationTitle("Wishlist")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        browserTarget = DekuLinkTarget(url: DekuLinks.home)
                    } label: {
                        Label("Browse Deku Deals", systemImage: "globe")
                    }
                }
            }
        }
        .dekuBrowser(target: $browserTarget) {
            Task { await store.refresh() }   // e.g. after adding on Deku
        }
        .sheet(item: $addSearch) { target in
            AddGameSheet(initialSearch: target.name, defaultStatus: .wishlist)
        }
        .task {
            if store.isConfigured { await store.refresh() }
        }
    }

    // MARK: List

    private var visible: [DekuWishlistItem] {
        searchText.isEmpty
            ? store.items
            : store.items.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var list: some View {
        List {
            if let updated = store.lastUpdated {
                Section {
                    EmptyView()
                } footer: {
                    Text("\(store.items.count) games · synced \(updated, format: .relative(presentation: .named))")
                }
            }
            ForEach(visible) { item in
                Button {
                    if let url = item.url {
                        browserTarget = DekuLinkTarget(url: url)
                    }
                } label: {
                    row(item)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .contextMenu {
                    Button {
                        addSearch = AddTarget(name: item.name)
                    } label: {
                        Label("Add to Library", systemImage: "plus.square.on.square")
                    }
                    Button {
                        if let url = item.url { browserTarget = DekuLinkTarget(url: url) }
                    } label: {
                        Label("View on Deku Deals", systemImage: "globe")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .searchable(text: $searchText, prompt: "Search wishlist")
        .refreshable { await store.refresh() }
        .overlay {
            if store.isLoading && store.items.isEmpty {
                ProgressView("Syncing wishlist…")
            } else if let error = store.errorMessage, store.items.isEmpty {
                ContentUnavailableView("Sync failed", systemImage: "wifi.exclamationmark",
                                       description: Text(error))
            } else if visible.isEmpty && !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }

    private func row(_ item: DekuWishlistItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "heart.fill")
                .font(.caption)
                .foregroundStyle(.pink.opacity(0.8))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                HStack(spacing: 4) {
                    if let added = item.addedAt {
                        Text("Added \(added, format: .dateTime.month().day().year())")
                    }
                    if let format = item.desiredFormat {
                        Text("· \(format)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .contentShape(.rect)
    }

    // MARK: Setup

    @State private var urlInput = ""

    private var setupPrompt: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "heart.text.square")
                    .font(.system(size: 44))
                    .foregroundStyle(LSTheme.purple)
                Text("Connect your Deku Deals wishlist")
                    .font(.title3.bold())
                Text("In Deku Deals: Settings → Sharing → enable “Allow my wishlist to be publicly viewed”, then paste the wishlist link here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                TextField("dekudeals.com/wishlist/…", text: $urlInput)
                    .textFieldStyle(.roundedBorder)
                    #if !os(macOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
                Button("Connect") {
                    store.configuredURL = urlInput
                    Task { await store.refresh() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(urlInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(28)
            .frame(maxWidth: 440)
        }
    }
}
