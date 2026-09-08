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
    /// 絞り込みで当たった名前。今の年の呼び名と同じなら nil（設計書 8.2）。
    /// **行の名前は差し替えない。**7 節の規則を破ると、木と原稿と年表で違う名前が出る。
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
        // 値は「その行に添える名前」。祖先や、呼び名そのものに当たった行は空文字になる。
        let hits: [String: String]? = q.isEmpty ? nil : matched(s, kind: kind, query: q, year: year)
        func row(_ path: String) -> TreeNode? {
            guard let n = s.nodes[path], n.kind == kind else { return nil }
            if let hits, hits[path] == nil { return nil }
            return TreeNode(path: path, name: n.displayName(at: year), category: n.category,
                            flags: n.flags,
                            matchedName: hits?[path].flatMap { $0.isEmpty ? nil : $0 },
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

    /// query に当たった節点と、その祖先すべて。
    /// 一周目で当たった行だけを入れ、二周目で祖先を足す。当たった行を先に全部入れておかないと、
    /// 「当たった行 A の祖先を辿る途中で、まだ処理していない当たった行 B に着く」ときに
    /// B の添える名前が空文字で潰れてしまう（辞書の走査順に依存してしまう）。
    private static func matched(_ s: Snapshot, kind: Kind, query: String, year: Int) -> [String: String] {
        var keep: [String: String] = [:]
        // 一周目。当たった行だけを入れる。
        for (path, n) in s.nodes where n.kind == kind {
            if let name = hitName(n, query: query, year: year) { keep[path] = name }
        }
        // 二周目。祖先を足す。**当たった行は上書きしない。**
        // 親の輪が残っていても止まるよう、辿った path を覚えて二度目で打ち切る。
        for path in Array(keep.keys) {
            var visited: Set<String> = [path]
            var cur = s.nodes[path]?.parentPath
            while let c = cur, visited.insert(c).inserted {
                if keep[c] == nil { keep[c] = "" }
                cur = s.nodes[c]?.parentPath
            }
        }
        return keep
    }

    /// 当たったかと、添える名前。当たっていなければ nil、
    /// 当たったが今の年の呼び名そのものなら空文字を返す。
    /// **複数当たったら最も新しい年のものを採る**（設計書 8.1）。
    static func hitName(_ n: IndexedNode, query: String, year: Int) -> String? {
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
        return best?.name ?? ""
    }
}
