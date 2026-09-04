extension Node {
    /// year での呼び名。year 以下で最も新しい別名。どの別名よりも前なら保存名。
    public func displayName(at year: Int) -> String {
        var best: Alias? = nil
        for a in aliases where a.from <= year {
            if best == nil || a.from > best!.from { best = a }
        }
        return best?.name ?? name
    }
}
