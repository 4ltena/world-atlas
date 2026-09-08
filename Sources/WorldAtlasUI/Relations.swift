import Foundation
import WorldAtlasCore
import WorldAtlasStore

/// 関連の一行（設計書 8.4）。
public struct RelatedNode: Equatable, Identifiable, Sendable {
    public var path: String
    /// その年の呼び名（設計書 7 節）。
    public var name: String
    /// 右に小さく添える語。「412 分離」「412–596」など。無ければ空。
    public var note: String
    /// 年カーソルの年に存在しないなら真。薄く出す。
    public var absent: Bool
    public var id: String { path }
}

public struct RelationGroup: Equatable, Identifiable, Sendable {
    public var title: String
    public var nodes: [RelatedNode]
    public var id: String { title }
}

public enum Relations {
    /// 開いている節点の関連。順は設計書 8.4 のとおりで、**空の組は出さない。**
    ///
    /// 逆向き（自分を由来に持つ節点、自分が支配する場所）は全走査で拾う。
    /// 66 件ほどの vault を前提にしている（設計書 15 節、千を超える規模は対象外）。
    public static func of(_ s: Snapshot, path: String, year: Int) -> [RelationGroup] {
        guard s.nodes[path] != nil else { return [] }

        func row(_ p: String, note: String = "") -> RelatedNode? {
            guard let n = s.nodes[p] else { return nil }
            return RelatedNode(path: p, name: n.displayName(at: year), note: note,
                               absent: !n.exists(at: year))
        }

        // ── 繋がり。由来の両方向（設計書 8.4）。
        var lineage: [RelatedNode] = []
        for l in (s.nodes[path]?.lineages ?? []).sorted(by: { $0.year < $1.year }) {
            guard let p = s.path(ofSavedName: l.origin) else { continue }
            if let r = row(p, note: "\(l.year) \(l.kind)") { lineage.append(r) }
        }
        for (p, n) in s.nodes.sorted(by: { $0.key < $1.key }) {
            for l in n.lineages where s.path(ofSavedName: l.origin) == path {
                if let r = row(p, note: "\(l.year) \(l.kind)") { lineage.append(r) }
            }
        }

        // ── その年の支配。場所なら支配する勢力、勢力なら支配している場所。
        var rules: [RelatedNode] = s.rulers(of: path, at: year).compactMap { row($0.path) }
        for (p, n) in s.nodes.sorted(by: { $0.key < $1.key }) {
            for r in n.rules where r.from <= year && (r.to.map { year < $0 } ?? true) {
                guard s.path(ofSavedName: r.polity) == path else { continue }
                let end = r.to.map { "\($0)" } ?? "現在"
                if let x = row(p, note: "\(r.from)–\(end)") { rules.append(x) }
            }
        }

        let out = s.refs[path]?.compactMap { row($0) } ?? []
        let back = s.backrefs[path]?.compactMap { row($0) } ?? []

        return [RelationGroup(title: "繋がり", nodes: lineage),
                RelationGroup(title: "この年の支配", nodes: rules),
                RelationGroup(title: "参照している", nodes: out),
                RelationGroup(title: "参照されている", nodes: back)]
            .filter { !$0.nodes.isEmpty }
    }
}
