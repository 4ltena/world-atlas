import Foundation
import WorldAtlasCore
import WorldAtlasStore

/// パンくずの一つ。押すとその節点へ移る。
public struct Crumb: Equatable, Identifiable, Sendable {
    public var path: String
    public var name: String
    public var id: String { path }
}

/// 原稿の頭に並べる事実。
public struct FactChip: Equatable, Identifiable, Sendable {
    public var label: String
    public var value: String
    public var id: String { label }
}

/// 原稿の欄の見出し部分。本文は BodyRenderer が別に作る。
public struct Header: Equatable, Sendable {
    public var crumbs: [Crumb]
    /// その年の呼び名。
    public var title: String
    /// 呼び名と保存名が違うときだけ入る（設計書 7 節）。
    public var savedName: String?
    public var category: String
    /// 並びを固定して出す。
    public var flags: [Flag]
    public var chips: [FactChip]
}

public enum Manuscript {
    /// 印を出す順。
    static let flagOrder: [Flag] = [.broken, .nameMismatch, .duplicate, .cycle]

    public static func header(_ s: Snapshot, path: String, year: Int, calendar c: CalendarDef) -> Header? {
        guard let n = s.nodes[path] else { return nil }

        var crumbs: [Crumb] = []
        var cur: IndexedNode? = n
        var seen: Set<String> = []
        while let x = cur, seen.insert(x.path).inserted {
            crumbs.append(Crumb(path: x.path, name: x.displayName(at: year)))
            cur = x.parentPath.flatMap { s.nodes[$0] }
        }
        crumbs.reverse()

        var chips = [FactChip(label: "期間", value: period(n, c))]
        let rulers = s.rulers(of: path, at: year)
        if !rulers.isEmpty {
            chips.append(FactChip(label: "支配", value: rulers.map { $0.displayName(at: year) }.joined(separator: "、")))
        }
        if !n.lineages.isEmpty {
            chips.append(FactChip(label: "由来", value: n.lineages.map { l in
                let origin = s.node(savedName: l.origin)?.displayName(at: l.year) ?? l.origin
                return "\(l.year) \(l.kind) ← \(origin)"
            }.joined(separator: "、")))
        }
        let kids = s.children[path]?.count ?? 0
        if kids > 0 { chips.append(FactChip(label: "直下", value: "\(kids) 件")) }

        let display = n.displayName(at: year)
        return Header(crumbs: crumbs, title: display,
                      savedName: display == n.name ? nil : n.name,
                      category: n.category,
                      flags: flagOrder.filter { n.flags.contains($0) },
                      chips: chips)
    }

    /// 期間のチップ。点の節点は年ひとつ、終わりが無ければ「現在」で閉じる。
    static func period(_ n: IndexedNode, _ c: CalendarDef) -> String {
        func y(_ base: Int) -> String {
            let v = base + c.offset
            return v > 0 ? "\(v)" : "前 \(1 - v)"
        }
        if n.isPoint { return "\(c.name) \(y(n.from)) 年" }
        guard let to = n.to else { return "\(c.name) \(y(n.from)) 年–現在" }
        return "\(c.name) \(y(n.from))–\(y(to)) 年"
    }
}
