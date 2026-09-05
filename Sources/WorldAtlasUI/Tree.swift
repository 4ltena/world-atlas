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
    public var children: [TreeNode]
    public var id: String { path }
}

public enum Tree {
    /// 型ひとつぶんの木。順は Snapshot の roots と children の順（開始年、同年は名前）。
    /// query が空でなければ、保存名か別名に query を含む節点と、その祖先だけを残す。
    /// 全文検索ではない（設計書 8.1）。
    public static func build(_ s: Snapshot, kind: Kind, year: Int, query: String = "") -> [TreeNode] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let keep: Set<String>? = q.isEmpty ? nil : matched(s, kind: kind, query: q)
        func row(_ path: String) -> TreeNode? {
            guard let n = s.nodes[path], n.kind == kind else { return nil }
            if let keep, !keep.contains(path) { return nil }
            return TreeNode(path: path, name: n.displayName(at: year), category: n.category,
                            flags: n.flags, children: (s.children[path] ?? []).compactMap(row))
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

    /// query に当たった節点と、その祖先すべて。
    private static func matched(_ s: Snapshot, kind: Kind, query: String) -> Set<String> {
        var keep: Set<String> = []
        for (path, n) in s.nodes where n.kind == kind {
            let hit = n.name.localizedCaseInsensitiveContains(query)
                || n.aliases.contains { $0.name.localizedCaseInsensitiveContains(query) }
            guard hit else { continue }
            // 既に入れてある節点に着いたら、その先の祖先はもう入っている。
            var cur: String? = path
            while let c = cur, keep.insert(c).inserted { cur = s.nodes[c]?.parentPath }
        }
        return keep
    }
}
