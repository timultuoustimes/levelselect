import Foundation

/// YouTube URL parsing + metadata via oEmbed (no API key). Playback uses the
/// privacy-enhanced embed; playlists embed as `videoseries` so YouTube's own
/// part navigation handles multi-part walkthroughs.
enum YouTubeService {
    struct Parsed: Sendable, Equatable {
        let kind: VideoKind
        let id: String          // video id or playlist id
    }

    struct Metadata: Sendable {
        let title: String
        let channel: String?
        let thumbnailURL: String?
    }

    /// Recognize watch/short/share/playlist URLs. A `list=` parameter wins
    /// (a video-in-playlist link means "add the playlist").
    static func parse(_ raw: String) -> Parsed? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed) else { return nil }
        if components.scheme == nil,
           let fixed = URLComponents(string: "https://" + trimmed) {
            components = fixed
        }
        let host = (components.host ?? "").lowercased()
        guard host.contains("youtube.com") || host.contains("youtu.be") else { return nil }

        let query = components.queryItems ?? []
        if let list = query.first(where: { $0.name == "list" })?.value, !list.isEmpty {
            return Parsed(kind: .playlist, id: list)
        }
        if host.contains("youtu.be") {
            let id = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return id.isEmpty ? nil : Parsed(kind: .video, id: id)
        }
        if let v = query.first(where: { $0.name == "v" })?.value, !v.isEmpty {
            return Parsed(kind: .video, id: v)
        }
        let path = components.path
        for prefix in ["/shorts/", "/embed/", "/live/"] where path.hasPrefix(prefix) {
            let id = String(path.dropFirst(prefix.count)).components(separatedBy: "/")[0]
            if !id.isEmpty { return Parsed(kind: .video, id: id) }
        }
        return nil
    }

    /// Title/channel/thumbnail via oEmbed. Fails soft — callers fall back to
    /// an editable placeholder title.
    static func metadata(for urlString: String) async -> Metadata? {
        var components = URLComponents(string: "https://www.youtube.com/oembed")!
        components.queryItems = [
            URLQueryItem(name: "url", value: urlString),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let url = components.url,
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let title = json["title"] as? String
        else { return nil }
        return Metadata(
            title: title,
            channel: json["author_name"] as? String,
            thumbnailURL: json["thumbnail_url"] as? String
        )
    }

    /// Embed URL for the in-app player (IFrame API enabled for the resume
    /// bridge). Resumes at the stored position — playlists also restore the
    /// last-watched part.
    static func embedURL(for video: GameVideo) -> URL? {
        var components = URLComponents(string: "https://www.youtube-nocookie.com/embed/")
        let start = max(0, Int(video.watchedSeconds.rounded(.down)) - 2)   // small rewind
        switch video.kind {
        case .video:
            components?.path = "/embed/\(video.youtubeID)"
            components?.queryItems = [
                URLQueryItem(name: "enablejsapi", value: "1"),
                URLQueryItem(name: "playsinline", value: "1"),
                URLQueryItem(name: "start", value: String(start)),
            ]
        case .playlist:
            components?.path = "/embed/videoseries"
            components?.queryItems = [
                URLQueryItem(name: "list", value: video.youtubeID),
                URLQueryItem(name: "index", value: String(video.watchedPartIndex)),
                URLQueryItem(name: "enablejsapi", value: "1"),
                URLQueryItem(name: "playsinline", value: "1"),
                URLQueryItem(name: "start", value: String(start)),
            ]
        }
        return components?.url
    }
}
