import Foundation

/// 一覧に並ぶ一件。外しても vault のディレクトリは消さない（設計書 4.1）。
public struct RecentVault: Codable, Equatable, Identifiable, Sendable {
    public var path: String
    /// 最後に開いたときの世界名。一覧に出す。
    public var world: String
    public var openedAt: Date
    /// 最後に開いたときの節点の数と世界の端（設計書 4.1 の三段目）。
    /// **一覧の窓は索引しない**ので、vault の窓が開いたときに書き戻した値をそのまま出す。
    /// Stage 2 が書いた JSON にはこの鍵が無いため、すべて省略可能にしてある。
    public var nodes: Int?
    public var from: Int?
    public var to: Int?
    public var id: String { path }
    public var url: URL { URL(fileURLWithPath: path) }

    public init(path: String, world: String, openedAt: Date,
                nodes: Int? = nil, from: Int? = nil, to: Int? = nil) {
        self.path = path; self.world = world; self.openedAt = openedAt
        self.nodes = nodes; self.from = from; self.to = to
    }
}

/// 最近使った vault の一覧。@AppStorage に入れられるよう JSON の文字列で持つ。
public enum RecentVaults {
    /// 覚えておく件数。
    public static let limit = 20

    /// @AppStorage の鍵。一覧の窓と vault の窓の両方が触るので、一箇所に置く。
    /// **値は既存の `VaultListView` の `@AppStorage("recentVaults")` と同じでなければならない。**
    /// 違う鍵にすると、書き戻した件数がどこにも出ない。
    public static let storageKey = "recentVaults"

    public static func decode(_ json: String) -> [RecentVault] {
        guard let data = json.data(using: .utf8),
              let list = try? JSONDecoder().decode([RecentVault].self, from: data) else { return [] }
        return list
    }

    public static func encode(_ list: [RecentVault]) -> String {
        guard let data = try? JSONEncoder().encode(list) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    /// 開いた vault を先頭へ。同じ path が既にあれば世界名と時刻を更新して動かす。
    public static func touch(_ list: [RecentVault], path: String, world: String, now: Date) -> [RecentVault] {
        // 開き直しただけでは索引していないので、前に記録した件数はそのまま持ち越す。
        let kept = list.first { $0.path == path }
        var out = list.filter { $0.path != path }
        out.insert(RecentVault(path: path, world: world, openedAt: now,
                               nodes: kept?.nodes, from: kept?.from, to: kept?.to), at: 0)
        return Array(out.prefix(limit))
    }

    /// 索引が済んだ vault の件数と端を書き込む。並びは動かさない。
    public static func record(_ list: [RecentVault], path: String,
                              nodes: Int, from: Int, to: Int) -> [RecentVault] {
        list.map {
            guard $0.path == path else { return $0 }
            var v = $0
            v.nodes = nodes; v.from = from; v.to = to
            return v
        }
    }

    public static func remove(_ list: [RecentVault], path: String) -> [RecentVault] {
        list.filter { $0.path != path }
    }
}
