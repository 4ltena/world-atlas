/// 世界の端。データから導く。
public struct Extent: Equatable, Sendable {
    public var lo: Int
    public var hi: Int
    public init(lo: Int, hi: Int) { self.lo = lo; self.hi = hi }

    /// 開始の最小を lo、終了・出来事・current の最大を hi にする。hi は lo より大きい。
    public static func compute(nodes: [Node], current: Int) -> Extent {
        var lo = nodes.map(\.from).min() ?? 1
        var hi = current
        for n in nodes {
            if let to = n.to { hi = max(hi, to) }
            hi = max(hi, n.from)
            for m in n.marks { hi = max(hi, m.year) }
            for a in n.aliases { hi = max(hi, a.from) }
        }
        if nodes.isEmpty { lo = 1 }
        if hi <= lo { hi = lo + 1 }
        return Extent(lo: lo, hi: hi)
    }
}
