import Foundation

/// 一覧に並ぶ一件。外しても vault のディレクトリは消さない（設計書 4.1）。
public struct RecentVault: Codable, Equatable, Identifiable, Sendable {
    public var path: String
    /// 最後に開いたときの世界名。一覧に出す。
    public var world: String
    public var openedAt: Date
    public var id: String { path }
    public var url: URL { URL(fileURLWithPath: path) }
}

/// 最近使った vault の一覧。@AppStorage に入れられるよう JSON の文字列で持つ。
public enum RecentVaults {
    /// 覚えておく件数。
    public static let limit = 20

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
        var out = list.filter { $0.path != path }
        out.insert(RecentVault(path: path, world: world, openedAt: now), at: 0)
        return Array(out.prefix(limit))
    }

    public static func remove(_ list: [RecentVault], path: String) -> [RecentVault] {
        list.filter { $0.path != path }
    }
}
