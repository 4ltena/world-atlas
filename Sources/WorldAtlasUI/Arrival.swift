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
    public static func middle(from: Int, to: Int) -> Int {
        let sum = from + to
        return sum >= 0 ? sum / 2 : (sum - 1) / 2
    }

    /// 探した名前が今の年に無いときの一行。要らなければ nil。
    ///
    /// `arrivedAs` は利用者が辿り着いた名前——検索で打った語、押したリンクの語である。
    /// **選択と年からは復元できない**ので、`VaultStore` が状態として持っている（設計書 7 節）。
    ///
    /// 二つの場合を一つの型で扱う。名前が違う場合と、そもそもその年に居ない場合である。
    /// **両方成り立つときは辿り着いた名前のほうを言う**——利用者が打った語に近い。
    public static func make(_ s: Snapshot, path: String, year: Int,
                            arrivedAs: String?, calendar c: CalendarDef) -> Arrival? {
        guard let n = s.nodes[path] else { return nil }
        let display = n.displayName(at: year)

        // ── 名前が違う場合。
        //
        // **ここで `name != display` へ絞ってはいけない。**displayName(at:) は節点自身の
        // 生死の期間を見ずに別名だけから決めるので、節点が終わった後の年でも「たまたま
        // 最後の別名と同じ名前」を返すことがある（北ヴェルダ王国が 596 年で終わった後の
        // 700 年でも、501 年からの別名がそのまま出てしまう）。そこを名前が同じという理由で
        // 弾くと、period(ofName:) が持つ本来の区間（別名の始まりが起点）ではなく、下の
        // 「その年に居ない場合」が使う節点全体の区間（節点自体の始まりが起点）で年を割って
        // しまい、真ん中の年がずれる。名前の一致では判定せず、period の中に居るかどうかだけ
        // で判定する。
        if let name = arrivedAs, let p = n.asNode.period(ofName: name) {
            // 期間の中にいるなら食い違っていない。呼び名の解決のほうが正しい。
            let end = p.to ?? s.extent.hi
            guard year < p.from || year > end else { return nil }
            let span = p.to == nil
                ? "\(c.short(p.from)) 年からの呼び名です"
                : "\(c.short(p.from))–\(c.short(end)) 年の呼び名です"
            return Arrival(message: "\(name) は \(span)", year: middle(from: p.from, to: end))
        }

        // ── その年に居ない場合。
        guard !n.exists(at: year) else { return nil }
        if n.isPoint {
            return Arrival(message: "\(display) は \(c.short(n.from)) 年の\(n.category)です",
                           year: n.from)
        }
        let end = n.to ?? s.extent.hi
        let span = n.to == nil
            ? "\(c.short(n.from)) 年からの\(n.category)です"
            : "\(c.short(n.from))–\(c.short(end)) 年の\(n.category)です"
        return Arrival(message: "\(display) は \(span)", year: middle(from: n.from, to: end))
    }
}
