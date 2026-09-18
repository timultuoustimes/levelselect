import Foundation

/// Your own order inside a Home shelf — `ThemeSettings.shelfOrderRaw`.
///
/// Asked for in build 38's user tests (Home) and waiting on a per-status order
/// string; V7 (09-18) deployed the field. A shelf with no order of yours keeps
/// the automatic one (pinned, then most recently played).
///
/// **Games that join a shelf later go in front of your arranged ones**, in the
/// automatic order: a game you just started is the one you want to see, and
/// a list that quietly files new arrivals at the end buries them. Games that
/// leave the shelf simply drop out; their place isn't kept.
enum ShelfOrder {
    /// Status raw value → game ids, in your order.
    typealias Orders = [String: [UUID]]

    static func decode(_ raw: String?) -> Orders {
        guard let raw, let data = raw.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: [String]].self, from: data) else { return [:] }
        return dict.mapValues { $0.compactMap(UUID.init(uuidString:)) }
    }

    static func encode(_ orders: Orders) -> String? {
        let clean = orders.filter { !$0.value.isEmpty }.mapValues { $0.map(\.uuidString) }
        guard !clean.isEmpty, let data = try? JSONEncoder.sorted.encode(clean) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// `automatic` in the shelf's usual order; the result in yours.
    static func arrange<T>(_ automatic: [T], id: (T) -> UUID, order: [UUID]?) -> [T] {
        guard let order, !order.isEmpty else { return automatic }
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        let newcomers = automatic.filter { rank[id($0)] == nil }
        let placed = automatic.filter { rank[id($0)] != nil }.sorted { rank[id($0)]! < rank[id($1)]! }
        return newcomers + placed
    }
}
