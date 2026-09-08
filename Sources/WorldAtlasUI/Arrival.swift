import Foundation
import WorldAtlasCore
import WorldAtlasStore

/// 原稿の見出しの下に出す一行（設計書 8.3）。
public struct Arrival: Equatable, Sendable {
    /// 出す文。
    public var message: String
    /// 「その年へ移る」の行き先。**基準暦の年**である。
    public var year: Int
}

public enum ArrivalNotice {
    /// 期間の真ん中。**下へ丸める。**Swift の `/` は 0 の側へ丸めるので、
    /// 負の年（暦の加算値で世界の前へ伸びる vault）でそのままだと食い違う。
    /// **足してから割らない。**年は front matter から来る任意の整数なので、
    /// 和が `Int` に収まらないことがある。右シフトは負でも下へ丸めるので、
    /// 半分ずつ足してから、両方が奇数のときだけ 1 を戻す。
    public static func middle(from: Int, to: Int) -> Int {
        (from >> 1) + (to >> 1) + (from & to & 1)
    }

    /// 探した名前が今の年に無いときの一行。要らなければ nil。
    ///
    /// `arrivedAs` は利用者が辿り着いた名前——検索で打った語、押したリンクの語である。
    /// **選択と年からは復元できない**ので、`VaultStore` が状態として持っている（設計書 7 節）。
    public static func make(_ s: Snapshot, path: String, year: Int,
                            arrivedAs: String?, calendar c: CalendarDef) -> Arrival? {
        guard let n = s.nodes[path] else { return nil }

        // **食い違っていないなら、何も言わない。**いま実在していて、辿り着いた名前で
        // 呼ばれているなら、利用者が探したものがそのまま画面に出ている。
        // **`name != display` でも「期間の外か」でもない。**前者は死んだ節点を見落とし
        // （呼び名の解決は生存期間を見ない）、後者は同じ名前へ二度戻る節点で
        // 古いほうの区間にいるときに誤って案内する（`period` は新しい区間しか返さない）。
        if let name = arrivedAs, n.exists(at: year), n.displayName(at: year) == name { return nil }

        // 点の節点は期間を持たない。名前で辿り着いても、言うことは一年である。
        if n.isPoint {
            guard !n.exists(at: year) else { return nil }
            return Arrival(message: "\(n.displayName(at: year)) は \(c.short(n.from)) 年の\(n.category)です",
                           year: n.from)
        }

        // 辿り着いた名前があるなら、その名前の期間を言う。**節点の期間より優先する**——
        // 利用者が打った語で呼ばれている年へ連れて行きたい。
        if let name = arrivedAs, let p = n.asNode.period(ofName: name) {
            let end = p.to ?? s.extent.hi
            let span = p.to == nil
                ? "\(c.short(p.from)) 年からの呼び名です"
                : "\(c.short(p.from))–\(c.short(end)) 年の呼び名です"
            return Arrival(message: "\(name) は \(span)", year: middle(from: p.from, to: end))
        }

        // 名前が無い、または引けない。実在しないなら期間を言う。
        guard !n.exists(at: year) else { return nil }
        let end = n.to ?? s.extent.hi
        let span = n.to == nil
            ? "\(c.short(n.from)) 年からの\(n.category)です"
            : "\(c.short(n.from))–\(c.short(end)) 年の\(n.category)です"
        return Arrival(message: "\(n.displayName(at: year)) は \(span)", year: middle(from: n.from, to: end))
    }
}
