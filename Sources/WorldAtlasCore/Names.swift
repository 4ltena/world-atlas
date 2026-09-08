extension Node {
    /// year での呼び名。year 以下で最も新しい別名。どの別名よりも前なら保存名。
    public func displayName(at year: Int) -> String {
        var best: Alias? = nil
        for a in aliases where a.from <= year {
            if best == nil || a.from > best!.from { best = a }
        }
        return best?.name ?? name
    }

    /// `name` がこの節点の呼び名として有効な期間。持っていない名前なら nil。
    ///
    /// 終わりの `to` が nil なら「節点の終わりまで」で、そこが `現在` の節点なら
    /// 呼ぶ側が世界の端で閉じる。**同じ名前へ二度戻る節点では、新しいほうを採る**——
    /// 利用者がその名前で探すとき、探しているのはたいてい今に近いほうである（設計書 8.1）。
    public func period(ofName name: String) -> (from: Int, to: Int?)? {
        // 境目は「次に始まる別名の前年」なので、始まりの年で並べ直してから見る。
        // front matter に書かれた順は当てにできない。
        var entries = aliases.sorted { $0.from < $1.from }

        // 保存名も一覧の先頭に並べる。ただし別名が節点の開始と同時か、それより前に
        // 始まっていると、保存名は一度も出ないので加えない（設計書 7 節）。
        if entries.first.map({ $0.from > from }) ?? true {
            entries.insert(Alias(from: from, name: self.name), at: 0)
        }

        // 同じ名前が複数回現れても、最も新しいもの（＝一覧の最後）を採る。
        guard let i = entries.lastIndex(where: { $0.name == name }) else { return nil }
        let start = entries[i].from
        let next = i + 1 < entries.count ? entries[i + 1].from - 1 : to
        return (start, next)
    }
}
