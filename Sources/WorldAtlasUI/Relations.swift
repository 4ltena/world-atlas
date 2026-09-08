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
    /// **`path` だけでは足りない。**由来は両方向から来るので、同じ節点が
    /// 「412 分離 ← B」と「596 統合 → B」の二行になることがある。どちらも別の事実で、
    /// 両方出したい。`ForEach` は `id` が重なると行を落とすか二重に描く。
    ///
    /// **文字列を繋げない。**区切りに使える「絶対に現れない文字」は無い——
    /// path にも note にも任意の文字が入りうるので、繋げた時点で単射でなくなり、
    /// 別々の二行が同じ id になって片方が消える。組のまま持てば境目が曖昧にならない。
    public var id: [String] { [path, note] }
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

        // path と note の両方が一致するときだけ重複として落とす。順は保つ。
        func dedup(_ rows: [RelatedNode]) -> [RelatedNode] {
            var seen: Set<[String]> = []
            return rows.filter { seen.insert($0.id).inserted }
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
        // **逆向きも `rulers(of:at:)` を通す。**`rules` を直に読むと、自分の子孫が
        // 支配を継承している場所を見落とす——場所→勢力の向きは継承込みで答えるのに、
        // 勢力→場所の向きだけ「自身に支配が書いてある節点」しか拾わないのは非対称である。
        // 同じ関数を両方向に使えば、二つの向きは作りのうえで自動的に一致する。
        var rules: [RelatedNode] = s.rulers(of: path, at: year).compactMap { row($0.path) }
        for (p, _) in s.nodes.sorted(by: { $0.key < $1.key }) {
            guard s.rulers(of: p, at: year).contains(where: { $0.path == path }) else { continue }
            if let x = row(p) { rules.append(x) }
        }

        // **参照している／参照されているにも dedup を掛ける。**別々のリンク文字列
        // （保存名と別名など）が同じ path へ解決すると、Indexer の逆参照は参照元を
        // 重ねて追加する——それ自体は正しい（原稿は本当に二度リンクしている）が、
        // note が常に空なのでここでは id が重なる。行を作る場所でまとめて弾く。
        let out = s.refs[path]?.compactMap { row($0) } ?? []
        let back = s.backrefs[path]?.compactMap { row($0) } ?? []

        return [RelationGroup(title: "繋がり", nodes: dedup(lineage)),
                RelationGroup(title: "この年の支配", nodes: dedup(rules)),
                RelationGroup(title: "参照している", nodes: dedup(out)),
                RelationGroup(title: "参照されている", nodes: dedup(back))]
            .filter { !$0.nodes.isEmpty }
    }
}
