import Foundation

/// 事実の出どころ。節点の識別子は保存名ではなく vault からの相対パスなので、
/// 保存名が重複していても総観の行から一つの節点を開ける。
public struct FactSource: Sendable {
    public var path: String
    public var node: Node
    public init(path: String, node: Node) { self.path = path; self.node = node }
}

public struct Fact: Equatable, Sendable {
    public var year: Int
    /// vault からの相対パス。識別子。
    public var path: String
    /// 保存名。
    public var node: String
    /// その年の呼び名。
    public var display: String
    public var category: String
    /// 動作や内容。点の出来事は空。
    public var text: String
    public init(year: Int, path: String, node: String, display: String, category: String, text: String) {
        self.year = year; self.path = path; self.node = node
        self.display = display; self.category = category; self.text = text
    }
}

public enum Facts {
    /// 種別ごとの始まりと終わりの語。無ければ 成立／消滅。
    public static func verbs(for category: String) -> (start: String, end: String) {
        switch category {
        case "人物": return ("生まれる", "没する")
        case "家系": return ("興る", "絶える")
        case "勢力": return ("成立", "消滅")
        case "法", "条": return ("制定", "失効")
        case "書物": return ("成立", "絶版")
        case "小冊": return ("刊行", "絶版")
        case "巻", "章": return ("書き始め", "書き終え")
        case "宿", "工房", "書店": return ("開く", "閉じる")
        case "刻印", "道具", "器物": return ("作られる", "失われる")
        default: return ("成立", "消滅")
        }
    }

    /// year の前後 window 年に起きたことを年順に集める。
    /// 出来事とは、点の節点、期間の始まりと終わり、別名の切り替わり、出来事の各行である。
    public static func around(year: Int, window: Int, sources: [FactSource]) -> [Fact] {
        let lo = year - window, hi = year + window
        func within(_ y: Int) -> Bool { lo <= y && y <= hi }
        var out: [Fact] = []
        var isPoint: [Bool] = []
        func add(_ f: Fact, point: Bool = false) { out.append(f); isPoint.append(point) }
        for src in sources {
            let n = src.node
            let v = verbs(for: n.category)
            func fact(_ y: Int, _ text: String, display: String? = nil) -> Fact {
                Fact(year: y, path: src.path, node: n.name, display: display ?? n.displayName(at: y),
                     category: n.category, text: text)
            }
            if n.isPoint {
                if within(n.from) { add(fact(n.from, ""), point: true) }
                continue
            }
            if within(n.from) { add(fact(n.from, v.start)) }
            if let to = n.to, within(to) { add(fact(to, v.end)) }
            for a in n.aliases where within(a.from) {
                add(fact(a.from, "→ \(a.name)", display: n.displayName(at: a.from - 1)))
            }
            for m in n.marks where within(m.year) {
                add(fact(m.year, m.label))
            }
        }
        // 年順。同年は点の出来事を先に、あとは path 昇順。**呼ぶ側の並びに任せない。**
        // sources は辞書（snapshot.nodes）から作られることが多く、その列挙順は
        // 索引を作り直すたびに変わりうる。ここで並びを決め切っておけば、要約値
        // （digest）も画面の「この年のできごと」欄も、索引を作り直すたびに勝手に
        // 入れ替わることがない。
        return out.enumerated().sorted { a, b in
            if a.element.year != b.element.year { return a.element.year < b.element.year }
            if isPoint[a.offset] != isPoint[b.offset] { return isPoint[a.offset] }
            return a.element.path < b.element.path
        }.map(\.element)
    }

    /// 一行の形。年、表示名、種別、内容（設計書 9 節）。
    public static func line(_ f: Fact) -> String {
        let head = "\(f.year): \(f.display)（\(f.category)）"
        return f.text.isEmpty ? head : head + " " + f.text
    }

    /// Stage 6 が Ollama に渡す文字列。この形はStage 6 でも変えない。
    public static func overviewInput(year: Int, window: Int, facts: [Fact], calendar: CalendarDef) -> String {
        var s = "対象の年: \(calendar.format(year))\n"
        s += "範囲: \(calendar.format(year - window)) から \(calendar.format(year + window))\n\n"
        for f in facts { s += line(f) + "\n" }
        s += "\n"
        return s
    }

    /// 総観の入力の要約値。生成した文の front matter に書き、次に開いたとき
    /// 今の材料から取り直した値と比べて「古い」を判定する（設計書 9 節）。
    ///
    /// **`hashValue` を使わない。**Swift の `hashValue` はプロセスごとに種が変わるので、
    /// 起動するたびに全部の年が「古い」になり、待ち行列が無限に回る。FNV-1a の
    /// 64 ビットを自前で取る。速さは要らない（一年ぶんの入力は数キロバイトである）。
    public static func digest(_ input: String) -> String {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in input.utf8 {
            h ^= UInt64(b)
            h = h &* 0x0000_0100_0000_01b3
        }
        // 16 桁に揃える。**桁を揃えなくても値そのものは正しく読み書きできる**——
        // 幅を可変にしても、書いた値と読んだ値は一致する。揃えるのは front matter に
        // 並んだ複数の記録を目で見比べやすくするためで、桁が飛び飛びだと同じかどうか
        // 読み取りにくい。
        return String(format: "%016lx", h)
    }
}
