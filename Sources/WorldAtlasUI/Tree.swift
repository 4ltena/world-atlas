import Foundation
import WorldAtlasCore
import WorldAtlasStore

/// 木の一行。子を入れ子で持ち、そのまま View の DisclosureGroup へ渡す。
public struct TreeNode: Equatable, Identifiable, Sendable {
    public var path: String
    /// その年の呼び名。
    public var name: String
    public var category: String
    public var flags: Set<Flag>
    /// 行の右端に薄く添える名前。今の年の呼び名と同じか、祖先としてだけ残った行なら nil
    /// （設計書 8.2）。**行の名前は差し替えない。**7 節の規則を破ると、木と原稿と年表で違う名前が出る。
    public var subLabel: String?
    /// 絞り込みで実際に当たった名前。**今の年の呼び名と同じでも入る。**利用者が辿り着いた
    /// 名前として `requestSelect(_:arrivedAs:)` へそのまま渡すためのもので、`subLabel` とは
    /// 別の役目を持つ——副の名前を省く判断と、到達名を覚える判断は別である。
    /// 祖先としてだけ残った行では nil。
    public var matchedName: String?
    public var children: [TreeNode]
    public var id: String { path }
}

public enum Tree {
    /// 型ひとつぶんの木。順は Snapshot の roots と children の順（開始年、同年は名前）。
    /// query が空でなければ、保存名か別名に query を含む節点と、その祖先だけを残す。
    /// 全文検索ではない（設計書 8.1）。
    public static func build(_ s: Snapshot, kind: Kind, year: Int, query: String = "") -> [TreeNode] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let hits: [String: RowMatch]? = q.isEmpty ? nil : matched(s, kind: kind, query: q, year: year)
        func row(_ path: String) -> TreeNode? {
            guard let n = s.nodes[path], n.kind == kind else { return nil }
            if let hits, hits[path] == nil { return nil }
            return TreeNode(path: path, name: n.displayName(at: year), category: n.category,
                            flags: n.flags,
                            subLabel: hits?[path]?.subLabel,
                            matchedName: hits?[path]?.matchedName,
                            children: (s.children[path] ?? []).compactMap(row))
        }
        return (s.roots[kind] ?? []).compactMap(row)
    }

    /// 子を持つ行の path。絞り込みのときに全部開くのに使う。
    public static func branches(_ nodes: [TreeNode]) -> Set<String> {
        var out: Set<String> = []
        func walk(_ n: TreeNode) {
            guard !n.children.isEmpty else { return }
            out.insert(n.path)
            n.children.forEach(walk)
        }
        nodes.forEach(walk)
        return out
    }

    /// 一行に添える二つの値。祖先としてだけ残った行はどちらも nil。
    struct RowMatch {
        /// 実際に当たった名前。今の年の呼び名と同じでも入る（設計書 7 節）。
        var matchedName: String?
        /// 行の右端に薄く添える名前。今の年の呼び名と同じなら nil。
        var subLabel: String?
    }

    /// query に当たった節点と、その祖先すべて。
    /// 一周目で当たった行だけを入れ、二周目で祖先を足す。**正しさのために二周へ分けているのではない。**
    /// 当たった行への書き込みは常に無条件の上書きなので、一周に混ぜて「当たり判定の途中で
    /// 祖先も埋める」形にしても、後で本人の当たりに処理が来た時点で祖先用の空の印はそのまま
    /// 上書きされる——辞書の走査順に結果は依存しない。二周に分けているのは、
    /// 「まず当たりを全部確定してから、祖先を辿る」という順のほうが素直に読めるからである。
    private static func matched(_ s: Snapshot, kind: Kind, query: String, year: Int) -> [String: RowMatch] {
        var keep: [String: RowMatch] = [:]
        // 一周目。当たった行だけを入れる。
        for (path, n) in s.nodes where n.kind == kind {
            if let hit = hitName(n, query: query, year: year) { keep[path] = hit }
        }
        // 二周目。祖先を足す。**当たった行は上書きしない。**
        // 親の輪が残っていても止まるよう、辿った path を覚えて二度目で打ち切る。
        for path in Array(keep.keys) {
            var visited: Set<String> = [path]
            var cur = s.nodes[path]?.parentPath
            while let c = cur, visited.insert(c).inserted {
                if keep[c] == nil { keep[c] = RowMatch(matchedName: nil, subLabel: nil) }
                cur = s.nodes[c]?.parentPath
            }
        }
        return keep
    }

    /// 当たったかと、その名前。当たっていなければ nil。
    /// **複数当たったら最も新しい年のものを採る**（設計書 8.1）。
    static func hitName(_ n: IndexedNode, query: String, year: Int) -> RowMatch? {
        let display = n.displayName(at: year)
        var hit = false
        // 保存名はどの別名よりも前なので、最も古い。Int.min を置く。
        var best: (from: Int, name: String)? = nil
        if n.name.localizedCaseInsensitiveContains(query) {
            hit = true
            if n.name != display { best = (Int.min, n.name) }
        }
        for a in n.aliases where a.name.localizedCaseInsensitiveContains(query) {
            hit = true
            guard a.name != display else { continue }
            if best == nil || a.from > best!.from { best = (a.from, a.name) }
        }
        guard hit else { return nil }
        // best が無ければ、当たったのは呼び名そのもの——実際に当たった名前は display になる。
        let matched = best?.name ?? display
        return RowMatch(matchedName: matched, subLabel: best?.name)
    }
}
