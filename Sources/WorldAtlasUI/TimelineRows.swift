import Foundation
import WorldAtlasCore
import WorldAtlasStore

/// 年表の一行ぶんの材料。描くのは Canvas の仕事で、ここは何を描くかだけを決める。
public struct TimelineRow: Equatable, Sendable, Identifiable {
    public var path: String
    /// その年の呼び名。行の高さが足りるときだけ名札として出す。
    public var name: String
    public var category: String
    public var from: Int
    /// nil なら現在まで。
    public var to: Int?
    public var isPoint: Bool
    /// 上段（開いている節点自身）か。
    public var isRoot: Bool
    /// 出来事。塗りの菱形。
    public var marks: [Mark]
    /// 改称。白抜きの菱形。
    public var renames: [Alias]
    /// 支配。場所の帯の下に敷く色帯。
    public var rules: [Rule]
    /// 由来。線。
    public var lineages: [Lineage]
    public var id: String { path }
}

public enum Timeline {
    /// 年表に出す行（設計書 8.6）。
    /// 節点を選んでいれば上段がその節点、下段が直下の子。
    /// 何も選んでいない（または選んだ節点が消えた）ときは、その型の直下の節点を並べ、自身の段は出さない。
    public static func rows(_ s: Snapshot, selected: String?, kind: Kind, year: Int) -> [TimelineRow] {
        func row(_ path: String, isRoot: Bool) -> TimelineRow? {
            guard let n = s.nodes[path] else { return nil }
            return TimelineRow(path: path, name: n.displayName(at: year), category: n.category,
                               from: n.from, to: n.to, isPoint: n.isPoint, isRoot: isRoot,
                               marks: n.marks, renames: n.aliases,
                               rules: clip(effectiveRules(s, path: path), from: n.from, to: n.to),
                               lineages: n.lineages)
        }
        // **選んでいる節点の型がレールと違うなら、選択は見ない。**
        // レールで型を替えたら年表も追随する（設計書 8.6）。選択そのものは残るので、
        // 元の型へ戻せば元の根に戻る。
        if let selected, s.nodes[selected]?.kind == kind {
            let head = row(selected, isRoot: true)
            let kids = (s.children[selected] ?? []).compactMap { row($0, isRoot: false) }
            return (head.map { [$0] } ?? []) + kids
        }
        return (s.roots[kind] ?? []).compactMap { row($0, isRoot: false) }
    }

    /// その節点に効いている支配。本人に書かれていなければ、書かれている最も近い祖先のものを使う
    /// （設計書 5 節。`Snapshot.rulers(of:at:)` と同じ辿り方）。親が輪になっていても必ず終わる。
    public static func effectiveRules(_ s: Snapshot, path: String) -> [Rule] {
        var seen: Set<String> = []
        var cur = s.nodes[path]
        while let n = cur, seen.insert(n.path).inserted {
            if !n.rules.isEmpty { return n.rules }
            cur = n.parentPath.flatMap { s.nodes[$0] }
        }
        return []
    }

    /// 支配を行の存続期間で切る。**祖先から継いだ支配は子より長い。**
    /// 切らないと、色帯がその行の帯の外へはみ出す（設計書 8.6）。
    /// 支配の区間は [開始, 終了)、行の期間は [from, to] だが、点数に直すとどちらも同じ線になる。
    public static func clip(_ rules: [Rule], from: Int, to: Int?) -> [Rule] {
        rules.compactMap { r in
            let lo = max(r.from, from)
            let hi: Int? = switch (r.to, to) {
            case let (a?, b?): min(a, b)
            case let (a?, nil): a
            case let (nil, b?): b
            case (nil, nil): nil
            }
            if let hi, hi <= lo { return nil }   // 行の外で終わる支配は落とす
            return Rule(from: lo, to: hi, polity: r.polity)
        }
    }

    /// 勢力の保存名 → 色と模様の番号。開始年、同年は名前で並べた順に固定する（設計書 14 節）。
    /// 索引の順に依存させると、節点が増えたときに色が入れ替わる。
    public static func polityIndices(_ s: Snapshot) -> [String: Int] {
        let sorted = s.nodes.values
            .filter { $0.kind == .polity && !$0.flags.contains(.broken) }
            .sorted { $0.from != $1.from ? $0.from < $1.from : $0.name < $1.name }
        var out: [String: Int] = [:]
        for (i, n) in sorted.enumerated() { out[n.name] = i }
        return out
    }
}
