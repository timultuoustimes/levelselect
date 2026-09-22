import Foundation

/// **Where a tracker's items came from — a descriptor and a link, never the
/// text.**
///
/// `TrackerSchemaRecord.sourcesJSON` has existed since V1 and was written by
/// nothing but the importer and the schema seeder: generation and paste
/// accepted a source type and an attribution and dropped the provenance
/// (Codex, build 40 static assessment, 09-21). It was one of the two "1.0
/// honesty leftovers" — a tracker should be able to say where it came from.
///
/// **What it records is Tim's decision (09-21): descriptors and URLs, never
/// pasted guide text.** A guide you pasted in is somebody else's writing;
/// keeping a copy would put it in your iCloud, your backups and every sync,
/// and the tracker already holds what you took from it. So a paste records
/// that it *was* pasted, and nothing of what was.
///
/// That rule is enforced here rather than trusted upstream. The generator
/// already sends only a type and a URL, but a record decoded from any payload
/// keeps those two fields and drops everything else — so a future server
/// change that added the text could not carry it into the store.
struct TrackerProvenance: Codable, Hashable {
    /// What kind of source: `"url"` and `"category"` from generation,
    /// `"paste"` and `"sheet"` from the list importer.
    var type: String
    /// The guide or sheet it came from, where there is one. Never set on a
    /// paste — a paste has no address, only content, and content is exactly
    /// what this does not keep.
    var url: String?

    init(type: String, url: String? = nil) {
        self.type = type
        let trimmed = url?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.url = (type == "paste" || trimmed?.isEmpty != false) ? nil : trimmed
    }

    static let pasted = TrackerProvenance(type: "paste")
    static func sheet(_ url: String) -> TrackerProvenance { TrackerProvenance(type: "sheet", url: url) }

    /// The `sources` a generated schema carries, reduced to type and URL.
    static func fromSchemaPayload(_ jsonData: Data) -> [TrackerProvenance] {
        guard let root = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let sources = root["sources"] as? [[String: Any]] else { return [] }
        return sources.compactMap { entry in
            guard let type = entry["type"] as? String, !type.isEmpty else { return nil }
            return TrackerProvenance(type: type, url: entry["url"] as? String)
        }
    }

    /// Everything already recorded plus what just arrived, oldest first, each
    /// once. A tracker built up from a guide and then a paste says both.
    ///
    /// Reads whatever `sourcesJSON` already holds through the same filter, so
    /// a row written by an older build — or restored from a backup — is
    /// reduced to type and URL the first time anything touches it.
    static func merged(existing: Data?, adding: [TrackerProvenance]) -> Data? {
        let previous = existing.flatMap { data -> [TrackerProvenance]? in
            guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
            return list.compactMap { entry in
                guard let type = entry["type"] as? String, !type.isEmpty else { return nil }
                return TrackerProvenance(type: type, url: entry["url"] as? String)
            }
        } ?? []
        var seen = Set<TrackerProvenance>()
        let all = (previous + adding).filter { seen.insert($0).inserted }
        guard !all.isEmpty else { return existing }
        return try? JSONEncoder().encode(all)
    }
}
