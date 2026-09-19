import SwiftUI

/// What's New and What's Coming, in the app.
///
/// Both were rows that opened Safari. They read the two JSON feeds the site
/// publishes from the content that already builds its changelog and roadmap
/// pages — see `NewsFeeds` for why that matters more than the screens do.

// MARK: - What's New

struct WhatsNewView: View {
    /// Set when this is shown automatically after an update, so the screen can
    /// lead with the build you just got rather than the whole history.
    var highlighting: Int?

    @Environment(\.dismiss) private var dismiss
    @State private var state: NewsFeeds.Result<NewsFeeds.Changelog>?

    var body: some View {
        SettingsPage(title: "What's New",
                     icon: "sparkles",
                     blurb: "Every build, newest first — what was added, what got better, and what was broken and isn't now.") {
            switch state {
            case nil:
                NewsLoadingSection(what: "the changelog")
            case .failed(let message):
                NewsFailureSection(message: message, url: AppLinks.changelog)
            case .fresh(let feed):
                releases(feed)
            case .cached(let feed, let fetched):
                releases(feed)
                StaleFooterSection(fetched: fetched)
            }
        }
        .task {
            if state == nil { state = await NewsFeeds.changelog() }
        }
    }

    @ViewBuilder
    private func releases(_ feed: NewsFeeds.Changelog) -> some View {
        ForEach(feed.releases) { release in
            Section {
                VStack(alignment: .leading, spacing: 3) {
                    Text(release.title)
                        .font(.headline)
                    Text(release.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)

                ForEach(release.items) { item in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.callout.weight(.medium))
                            if !item.detail.isEmpty {
                                Text(item.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } icon: {
                        Image(systemName: item.kind.icon)
                            .foregroundStyle(LSTheme.accent)
                            .accessibilityLabel(item.kind.label)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                HStack {
                    Text(release.version)
                    if release.build != nil, release.build == highlighting {
                        // Only when this screen came up on its own after an
                        // update — otherwise it labels the top of a list you
                        // opened deliberately, which tells you nothing.
                        Text("· Just installed")
                            .foregroundStyle(LSTheme.accent)
                    }
                    Spacer()
                    Text(release.date.formatted(date: .abbreviated, time: .omitted))
                }
            }
        }

        Section {
            ExternalSettingsRow(title: "Read the full notes",
                                icon: "text.book.closed", url: AppLinks.changelog)
        } footer: {
            Text("Each entry above is the short version. The site has the whole thing.")
        }
    }
}

// MARK: - What's Coming

struct WhatsComingView: View {
    @State private var state: NewsFeeds.Result<NewsFeeds.Roadmap>?

    var body: some View {
        SettingsPage(title: "What's Coming",
                     icon: "map",
                     blurb: "A direction, not a set of promises — what's being worked on now, what's next, and what's being explored.") {
            switch state {
            case nil:
                NewsLoadingSection(what: "the roadmap")
            case .failed(let message):
                NewsFailureSection(message: message, url: AppLinks.roadmap)
            case .fresh(let feed):
                board(feed)
            case .cached(let feed, let fetched):
                board(feed)
                StaleFooterSection(fetched: fetched)
            }
        }
        .task {
            if state == nil { state = await NewsFeeds.roadmap() }
        }
    }

    @ViewBuilder
    private func board(_ feed: NewsFeeds.Roadmap) -> some View {
        ForEach(feed.horizons) { horizon in
            Section {
                ForEach(horizon.items) { item in
                    entry(item.title, item.detail)
                }
            } header: {
                HStack(spacing: 7) {
                    Circle()
                        .fill(Color(hex: horizon.color) ?? LSTheme.accent)
                        .frame(width: 8, height: 8)
                    Text(horizon.name)
                    Text("· \(horizon.note)")
                        .foregroundStyle(.secondary)
                }
            }
        }

        Section {
            ForEach(feed.notPlanned) { item in
                entry(item.title, item.detail)
            }
        } header: {
            Text("Not planned")
        } footer: {
            // The reviewed date is the whole reason to trust a roadmap in an
            // app: it says when someone last looked at it, rather than leaving
            // you to guess from how old the app is.
            Text("\(feed.disclaimer) Last reviewed \(feed.reviewed).")
        }

        Section {
            SettingsRow(title: "What's New", icon: "sparkles") { WhatsNewView() }
        } footer: {
            Text("For what's already shipped.")
        }
    }

    private func entry(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.callout.weight(.medium))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - The three states these two share

private struct NewsLoadingSection: View {
    let what: String

    var body: some View {
        Section {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Fetching \(what)…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }
}

/// Offline, or the site is down.
///
/// Says which, and offers the browser — the thing this screen replaced is
/// still the fallback when the screen can't do its job.
private struct NewsFailureSection: View {
    let message: String
    let url: URL

    var body: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Couldn't reach levelselect.app")
                        .font(.callout.weight(.medium))
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "wifi.slash")
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
            ExternalSettingsRow(title: "Open it in your browser",
                                icon: "safari", url: url)
        } footer: {
            Text("Nothing was lost — this page is only ever a copy of what's on the site.")
        }
    }
}

/// Shown under cached content so a stale roadmap can't pass for a current one.
private struct StaleFooterSection: View {
    let fetched: Date

    var body: some View {
        Section {
        } footer: {
            Text("Offline — showing what was last fetched \(fetched.formatted(.relative(presentation: .named))).")
        }
    }
}
