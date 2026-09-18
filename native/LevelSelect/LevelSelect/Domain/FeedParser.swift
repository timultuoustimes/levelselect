import Foundation

/// One story from a site's feed, as the reader holds it.
///
/// Held in memory and in the Caches directory, never in the store: what gets
/// synced is only what you did with a story (`NewsItemState`). A story is the
/// site's headline, a sentence or two of its summary, and where to read it —
/// the reader sends you to the site rather than showing the article.
struct FeedStory: Identifiable, Hashable, Codable, Sendable {
    /// The feed's own id for the item: `guid`/`id`, or the link without one.
    var guid: String
    var feedID: UUID
    var title: String
    var link: URL?
    var published: Date?
    /// Plain text, trimmed to a couple of sentences.
    var summary: String?
    var imageURL: URL?
    /// The feed's own category tags ("Reviews", "Nintendo Switch 2").
    var categories: [String] = []

    var id: String { "\(feedID.uuidString)|\(guid)" }
}

/// A parsed feed: what it calls itself, and its stories.
struct ParsedFeed: Sendable {
    var title: String
    var siteURL: URL?
    var stories: [FeedStory]
}

/// RSS 2.0, RSS 1.0 (RDF) and Atom, with Foundation's `XMLParser`.
///
/// **Images come from wherever the site put them**, in this order: a Media
/// RSS `media:content`/`media:thumbnail`, an image `enclosure`, then the first
/// `<img>` in the item's HTML. The Nintendo Life family, Game Informer and
/// IGN use the first; WordPress sites mostly the last. A story with none is
/// still a story — the layouts are drawn to read without art.
enum FeedParser {
    static func parse(_ data: Data, feedID: UUID, base: URL? = nil) -> ParsedFeed? {
        let delegate = Delegate(feedID: feedID, base: base)
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.delegate = delegate
        _ = parser.parse()
        // A page that isn't a feed parses as XML with no channel — or fails
        // partway through its HTML. Either way it is not a feed.
        guard delegate.sawFeedRoot else { return nil }
        return ParsedFeed(title: delegate.feedTitle.trimmed,
                          siteURL: delegate.siteURL,
                          stories: delegate.stories)
    }

    /// Plain text from a summary that is usually HTML: tags dropped, entities
    /// decoded, whitespace folded, cut at a sentence near `limit` characters.
    static func plainText(_ html: String, limit: Int = 240) -> String {
        // Block tags part words; inline ones (<b>, <a>) sit inside them.
        var text = html.replacingOccurrences(
            of: "</?(p|br|div|li|ul|ol|h[1-6]|blockquote|figure|figcaption|tr|td)\\b[^>]*>",
            with: " ", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = decodeEntities(text)
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmed
        guard text.count > limit else { return text }
        let cut = String(text.prefix(limit))
        if let stop = cut.range(of: ". ", options: .backwards), cut.distance(from: cut.startIndex, to: stop.lowerBound) > limit / 2 {
            return String(cut[..<stop.lowerBound]) + "."
        }
        return cut.trimmed + "…"
    }

    static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = s
        let named = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&apos;": "'",
                     "&#39;": "'", "&nbsp;": " ", "&rsquo;": "’", "&lsquo;": "‘",
                     "&rdquo;": "”", "&ldquo;": "“", "&mdash;": "—", "&ndash;": "–",
                     "&hellip;": "…", "&eacute;": "é"]
        for (k, v) in named { out = out.replacingOccurrences(of: k, with: v) }
        // Numeric: &#8217; and &#x2019;
        let pattern = "&#(x?)([0-9a-fA-F]+);"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return out }
        let ns = out as NSString
        var result = ""
        var last = 0
        for m in regex.matches(in: out, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let hex = ns.substring(with: m.range(at: 1)) == "x"
            let digits = ns.substring(with: m.range(at: 2))
            if let code = UInt32(digits, radix: hex ? 16 : 10), let scalar = Unicode.Scalar(code) {
                result.append(Character(scalar))
            } else {
                result += ns.substring(with: m.range)
            }
            last = m.range.location + m.range.length
        }
        result += ns.substring(from: last)
        return result
    }

    /// The first `<img src>` in a block of HTML.
    static func firstImage(inHTML html: String, base: URL?) -> URL? {
        guard let regex = try? NSRegularExpression(
            pattern: "<img[^>]+src\\s*=\\s*[\"']([^\"']+)[\"']", options: .caseInsensitive) else { return nil }
        let ns = html as NSString
        for m in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let src = decodeEntities(ns.substring(with: m.range(at: 1)))
            // Tracking pixels and feed-flare buttons are images too.
            let lower = src.lowercased()
            if lower.contains("feedburner") || lower.contains("pixel") || lower.hasSuffix(".gif") { continue }
            if let url = URL(string: src, relativeTo: base)?.absoluteURL, url.scheme?.hasPrefix("http") == true {
                return url
            }
        }
        return nil
    }

    // MARK: Dates

    private static let rfc822: [DateFormatter] = {
        ["EEE, dd MMM yyyy HH:mm:ss zzz", "EEE, dd MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm:ss zzz",
         "EEE, d MMM yyyy HH:mm:ss Z", "dd MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm zzz",
         "EEE, dd MMM yyyy HH:mm:ss"].map {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "UTC")
            f.dateFormat = $0
            return f
        }
    }()

    static func date(_ raw: String) -> Date? {
        let s = raw.trimmed
        if s.isEmpty { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        // Some sites send the zone as a US abbreviation ("CDT") — DateFormatter
        // knows the common ones.
        for f in rfc822 { if let d = f.date(from: s) { return d } }
        return nil
    }

    // MARK: Delegate

    private final class Delegate: NSObject, XMLParserDelegate {
        let feedID: UUID
        let base: URL?
        init(feedID: UUID, base: URL?) { self.feedID = feedID; self.base = base }

        var sawFeedRoot = false
        var feedTitle = ""
        var siteURL: URL?
        var stories: [FeedStory] = []

        private var inItem = false
        private var text = ""
        private var item = Item()
        private var depth = 0
        private var itemDepth = 0

        struct Item {
            var guid = ""
            var title = ""
            var link = ""
            var published = ""
            var summary = ""
            var content = ""
            var image: String?
            var categories: [String] = []
        }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            depth += 1
            text = ""
            let tag = name.lowercased()
            switch tag {
            case "rss", "feed", "rdf:rdf", "channel": sawFeedRoot = true
            case "item", "entry":
                inItem = true
                itemDepth = depth
                item = Item()
            case "link":
                // Atom: <link rel="alternate" href="…"/>. RSS: text content.
                if let href = attributes["href"] {
                    let rel = attributes["rel"] ?? "alternate"
                    if inItem {
                        if rel == "alternate" && item.link.isEmpty { item.link = href }
                        if rel == "enclosure", (attributes["type"] ?? "").hasPrefix("image"), item.image == nil { item.image = href }
                    } else if rel == "alternate" && siteURL == nil {
                        siteURL = URL(string: href)
                    }
                }
            case "media:content", "media:thumbnail":
                guard inItem, let url = attributes["url"] else { break }
                let type = attributes["type"] ?? ""
                let medium = attributes["medium"] ?? ""
                let looksImage = type.hasPrefix("image") || medium == "image"
                    || (type.isEmpty && medium.isEmpty)
                // Keep the first; a thumbnail never displaces a content image.
                if looksImage && item.image == nil { item.image = url }
            case "enclosure":
                if inItem, let url = attributes["url"], (attributes["type"] ?? "").hasPrefix("image"),
                   item.image == nil { item.image = url }
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            text += String(data: CDATABlock, encoding: .utf8) ?? ""
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                    qualifiedName: String?) {
            defer { depth -= 1 }
            let tag = name.lowercased()
            if inItem {
                switch tag {
                case "title" where depth == itemDepth + 1: item.title = text
                case "link" where item.link.isEmpty: item.link = text.trimmed
                case "guid", "id": if item.guid.isEmpty { item.guid = text.trimmed }
                case "pubdate", "published", "dc:date", "updated":
                    if item.published.isEmpty { item.published = text }
                case "description", "summary": if item.summary.isEmpty { item.summary = text }
                case "content:encoded", "content": if item.content.isEmpty { item.content = text }
                case "category":
                    let c = text.trimmed
                    if !c.isEmpty { item.categories.append(FeedParser.decodeEntities(c)) }
                case "item", "entry":
                    inItem = false
                    finish()
                default: break
                }
            } else {
                switch tag {
                case "title" where feedTitle.isEmpty: feedTitle = FeedParser.decodeEntities(text)
                case "link" where siteURL == nil:
                    if let url = URL(string: text.trimmed), url.scheme != nil { siteURL = url }
                default: break
                }
            }
            text = ""
        }

        private func finish() {
            let title = FeedParser.plainText(item.title, limit: 300)
            guard !title.isEmpty else { return }
            let link = URL(string: item.link.trimmed, relativeTo: base ?? siteURL)?.absoluteURL
            let guid = item.guid.isEmpty ? (link?.absoluteString ?? title) : item.guid
            let html = item.summary.isEmpty ? item.content : item.summary
            var image = item.image.flatMap { URL(string: FeedParser.decodeEntities($0), relativeTo: link)?.absoluteURL }
            if image == nil {
                image = FeedParser.firstImage(inHTML: item.summary + item.content, base: link)
            }
            let summary = FeedParser.plainText(html)
            stories.append(FeedStory(
                guid: guid, feedID: feedID, title: title, link: link,
                published: FeedParser.date(item.published),
                summary: summary.isEmpty || summary == title ? nil : summary,
                imageURL: image,
                categories: item.categories))
        }
    }
}

/// Finding the feed behind a site address.
///
/// People paste the site, not the feed — "nintendolife.com", not
/// "/feeds/latest". Sites say where their feed is in the page head with
/// `<link rel="alternate" type="application/rss+xml">`, which is what every
/// reader has always used.
enum FeedDiscovery {
    /// Feed addresses a page's HTML advertises, in page order.
    static func feedLinks(inHTML html: String, base: URL) -> [URL] {
        guard let tagRegex = try? NSRegularExpression(pattern: "<link[^>]+>", options: .caseInsensitive)
        else { return [] }
        let ns = html as NSString
        var out: [URL] = []
        for m in tagRegex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let tag = ns.substring(with: m.range)
            let lower = tag.lowercased()
            guard lower.contains("alternate"),
                  lower.contains("application/rss+xml") || lower.contains("application/atom+xml")
                    || lower.contains("application/rdf+xml"),
                  let href = attribute("href", in: tag),
                  let url = URL(string: FeedParser.decodeEntities(href), relativeTo: base)?.absoluteURL
            else { continue }
            // Comment feeds are a feed, but never the one anyone meant.
            if url.absoluteString.lowercased().contains("comments") { continue }
            if !out.contains(url) { out.append(url) }
        }
        return out
    }

    /// What someone typed, as a URL: a scheme added, spaces trimmed.
    static func normalized(_ typed: String) -> URL? {
        var s = typed.trimmed
        guard !s.isEmpty, !s.contains(" ") else { return nil }
        if s.lowercased().hasPrefix("feed://") { s = "https://" + s.dropFirst(7) }
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") { s = "https://" + s }
        guard let url = URL(string: s), url.host?.contains(".") == true else { return nil }
        return url
    }

    /// The same feed however it was spelled: scheme, `www.` and a trailing
    /// slash don't make a second subscription.
    static func key(_ url: String) -> String {
        var s = url.trimmed.lowercased()
        for prefix in ["https://", "http://", "feed://"] where s.hasPrefix(prefix) { s.removeFirst(prefix.count) }
        if s.hasPrefix("www.") { s.removeFirst(4) }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: "\(name)\\s*=\\s*[\"']([^\"']+)[\"']", options: .caseInsensitive) else { return nil }
        let ns = tag as NSString
        guard let m = regex.firstMatch(in: tag, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: m.range(at: 1))
    }
}

/// OPML, the file every reader exports — Inoreader, Feedly, NetNewsWire.
///
/// Folders are kept, because choosing which folders to bring in is the whole
/// import: Tim's export has a Gaming folder next to gardening and privacy, and
/// only one of those belongs here.
enum OPMLParser {
    struct Entry: Hashable, Sendable {
        var title: String
        var feedURL: String
        var siteURL: String?
        var folder: String?

        /// Inoreader writes its own newsletters and bundles as `name@ino.to`,
        /// which no other reader can fetch.
        var isFetchable: Bool {
            let lower = feedURL.lowercased()
            return lower.hasPrefix("http://") || lower.hasPrefix("https://")
        }
    }

    static func parse(_ data: Data) -> [Entry] {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        _ = parser.parse()
        return delegate.entries
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var entries: [Entry] = []
        /// Folder names, innermost last; nil for an outline that is a feed.
        private var stack: [String?] = []

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            guard name.lowercased() == "outline" else { return }
            let title = attributes["title"] ?? attributes["text"] ?? ""
            if let url = attributes["xmlUrl"] ?? attributes["xmlurl"] {
                let folder = stack.compactMap { $0 }.last
                entries.append(Entry(title: FeedParser.decodeEntities(title), feedURL: url,
                                     siteURL: attributes["htmlUrl"] ?? attributes["htmlurl"],
                                     folder: folder.map(FeedParser.decodeEntities)))
                stack.append(nil)
            } else {
                stack.append(title)
            }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                    qualifiedName: String?) {
            if name.lowercased() == "outline", !stack.isEmpty { stack.removeLast() }
        }
    }
}

extension String {
    fileprivate var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
