import Foundation
import SwiftData

/// Feeds you follow and what you did with their stories.
///
/// **Schema V7.** Every write here is to a record type CloudKit Production
/// does not have until Tim deploys V7, so nothing calls these on a Production
/// build before `SchemaDeploy.v7Fields` — the News tab isn't shown until then.
///
/// **`muted` means off.** A feed you switch off stays in your list, isn't
/// fetched, and keeps its saved stories; the mockup Tim approved on 09-17 says
/// "turning a feed off stops fetching; its saved stories stay". Nothing had
/// shipped on the field, so it takes the meaning the screen needs.
extension Repository {
    func liveFeeds() -> [NewsFeed] {
        let all = (try? context.fetch(FetchDescriptor<NewsFeed>())) ?? []
        return all.filter { $0.deletedAt == nil }
            .sorted { ($0.sortIndex, $0.createdAt) < ($1.sortIndex, $1.createdAt) }
    }

    /// The starter feeds, once.
    ///
    /// Skipped if any feed record exists, live or deleted — a deleted starter
    /// is a choice, and a second device must not undo it. Two fresh devices
    /// can still both seed before either has synced; `dedupeFeeds` folds those.
    @discardableResult
    func seedStarterFeedsIfNeeded() -> Bool {
        let any = (try? context.fetchCount(FetchDescriptor<NewsFeed>())) ?? 0
        guard any == 0 else { return false }
        for (i, entry) in FeedCatalog.startsOn.enumerated() {
            let feed = NewsFeed(urlString: entry.feedURL, title: entry.name)
            feed.siteURLString = entry.siteURL
            feed.sortIndex = i
            context.insert(feed)
        }
        persist()
        return true
    }

    /// One record per feed address, keeping the oldest. Two devices seeding
    /// the same starter list before they have synced is the usual cause.
    func dedupeFeeds() {
        let feeds = liveFeeds().sorted { $0.createdAt < $1.createdAt }
        var seen: [String: NewsFeed] = [:]
        var changed = false
        for feed in feeds {
            let key = FeedDiscovery.key(feed.urlString)
            if let keeper = seen[key] {
                // Off wins only if both are off.
                keeper.muted = keeper.muted && feed.muted
                feed.deletedAt = .now
                touch(feed)
                changed = true
            } else {
                seen[key] = feed
            }
        }
        if changed { persist() }
    }

    func feed(forURL url: String) -> NewsFeed? {
        let key = FeedDiscovery.key(url)
        return liveFeeds().first { FeedDiscovery.key($0.urlString) == key }
    }

    /// Follow a feed, or switch an existing one back on.
    @discardableResult
    func follow(url: String, title: String, siteURL: String?, folder: String? = nil) -> NewsFeed {
        if let existing = feed(forURL: url) {
            if existing.muted {
                existing.muted = false
                touch(existing)
                persist()
            }
            return existing
        }
        let feed = NewsFeed(urlString: url, title: title)
        feed.siteURLString = siteURL
        feed.folder = folder
        feed.sortIndex = (liveFeeds().map(\.sortIndex).max() ?? -1) + 1
        context.insert(feed)
        persist()
        return feed
    }

    func setFeed(_ feed: NewsFeed, on: Bool) {
        guard feed.muted == on else { return }
        feed.muted = !on
        touch(feed)
        persist()
    }

    func renameFeed(_ feed: NewsFeed, to title: String) {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, t != feed.title else { return }
        feed.title = t
        touch(feed)
        persist()
    }

    /// Unfollow. Saved stories from it stay saved.
    func unfollow(_ feed: NewsFeed) {
        feed.deletedAt = .now
        touch(feed)
        persist()
    }

    // MARK: Story state

    func storyStates() -> [NewsItemState] {
        ((try? context.fetch(FetchDescriptor<NewsItemState>())) ?? []).filter { $0.deletedAt == nil }
    }

    private func state(for story: FeedStory, creating: Bool) -> NewsItemState? {
        let guid = story.guid
        let feedID: UUID? = story.feedID
        var descriptor = FetchDescriptor<NewsItemState>(
            predicate: #Predicate { $0.guid == guid && $0.feedID == feedID && $0.deletedAt == nil })
        descriptor.fetchLimit = 1
        if let found = try? context.fetch(descriptor).first { return found }
        guard creating else { return nil }
        let s = NewsItemState(guid: story.guid)
        s.feedID = story.feedID
        s.title = story.title
        s.linkString = story.link?.absoluteString
        s.publishedAt = story.published
        context.insert(s)
        return s
    }

    /// Opened. Only stories you've touched are stored — see `NewsItemState`.
    func markRead(_ story: FeedStory) {
        guard let s = state(for: story, creating: true), !s.read else { return }
        s.read = true
        touch(s)
        persist()
    }

    func setSaved(_ story: FeedStory, _ saved: Bool) {
        guard let s = state(for: story, creating: saved) else { return }
        guard s.saved != saved else { return }
        s.saved = saved
        // A record kept only to say "saved" goes when it stops saying it.
        if !saved && !s.read { s.deletedAt = .now }
        touch(s)
        persist()
    }

    /// Unsaving from the Saved list, where there may be no live story.
    func unsave(_ state: NewsItemState) {
        state.saved = false
        if !state.read { state.deletedAt = .now }
        touch(state)
        persist()
    }

    func setRead(_ state: NewsItemState, _ read: Bool) {
        guard state.read != read else { return }
        state.read = read
        touch(state)
        persist()
    }
}

// MARK: - Synced settings strings (V7)

extension Repository {
    private func settingsRow() -> ThemeSettings {
        if let row = (try? context.fetch(FetchDescriptor<ThemeSettings>()))?
            .sorted(by: { $0.createdAt < $1.createdAt }).first {
            return row
        }
        let row = ThemeSettings()
        context.insert(row)
        return row
    }

    /// `ThemeSettings.suggestionPrefsRaw` — see `SuggestionPrefs`.
    func setSuggestionPrefs(_ raw: String) {
        guard SchemaDeploy.v7Fields else { return }
        let row = settingsRow()
        guard row.suggestionPrefsRaw != raw else { return }
        row.suggestionPrefsRaw = raw
        row.updatedAt = .now
        persist()
    }
}

extension Repository {
    /// `ThemeSettings.shelfOrderRaw` — see `ShelfOrder`. An empty list puts
    /// the shelf back on the automatic order.
    func setShelfOrder(_ status: GameStatus, _ ids: [UUID]) {
        guard SchemaDeploy.v7Fields else { return }
        let row = (try? context.fetch(FetchDescriptor<ThemeSettings>()))?
            .sorted(by: { $0.createdAt < $1.createdAt }).first ?? {
                let fresh = ThemeSettings()
                context.insert(fresh)
                return fresh
            }()
        var orders = ShelfOrder.decode(row.shelfOrderRaw)
        orders[status.rawValue] = ids.isEmpty ? nil : ids
        let raw = ShelfOrder.encode(orders)
        guard raw != row.shelfOrderRaw else { return }
        row.shelfOrderRaw = raw
        row.updatedAt = .now
        persist()
    }
}
