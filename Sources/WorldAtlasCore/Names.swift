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
    /// **`displayName(at:)` から導く。**同じことを二か所で別々に決めると食い違う——
    /// 同じ年に別名が二つ書かれていたとき、木に出る名前と、この期間が指す名前が割れる。
    /// 呼び名が変わりうるのは節点の始まりと各別名の始まりだけなので、その候補年でだけ引く。
    /// 別名は一節点あたり数個なので、二重に走っても足りる。
    ///
    /// 返す期間は**必ず節点の生きている範囲に収まる。**節点の開始より前に始まる別名は
    /// 開始年から効き、終わりより後に始まる別名は一度も出ないので nil になる。
    /// 終わりの `to` が nil なら「節点の終わりまで」で、そこが `現在` の節点なら
    /// 呼ぶ側が世界の端で閉じる。同じ名前へ二度戻る節点では、**新しいほうの区間を採る。**
    public func period(ofName name: String) -> (from: Int, to: Int?)? {
        var years = [from]
        for a in aliases where a.from > from { years.append(a.from) }
        if let to { years = years.filter { $0 <= to } }
        years = Array(Set(years)).sorted()

        guard let last = years.indices.last(where: { displayName(at: years[$0]) == name })
        else { return nil }
        // ひと続きの区間の始まりまで遡る。間に別の名前を挟んでいたら、そこで切れている。
        var first = last
        while first > 0, displayName(at: years[first - 1]) == name { first -= 1 }
        return (years[first], last + 1 < years.count ? years[last + 1] - 1 : to)
    }
}
