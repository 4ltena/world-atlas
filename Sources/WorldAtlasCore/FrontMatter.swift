import Foundation
import Yams

public enum FrontMatter {
    public struct Split: Equatable, Sendable {
        public var yaml: String
        public var body: String
        /// 本文の最初の行のファイル内行番号（1 始まり）。
        public var bodyLine: Int
    }

    /// 先頭の `---` から次の `---` までを YAML として切り出す。改行は LF に揃える。
    public static func split(_ text: String) -> Split? {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first == "---" else { return nil }
        guard let close = lines.dropFirst().firstIndex(of: "---") else { return nil }
        let yaml = lines[1..<close].map(String.init).joined(separator: "\n")
        let bodyLines = lines[(close + 1)...]
        let body = bodyLines.map(String.init).joined(separator: "\n")
        return Split(
            yaml: yaml.isEmpty ? "" : yaml + "\n",
            body: body,
            bodyLine: close + 2
        )
    }
}

extension FrontMatter {
    public static func parse(_ text: String, kind: Kind) throws(FrontMatterError) -> Node {
        guard let split = split(text) else {
            throw FrontMatterError(line: 1, message: "先頭に --- で囲んだ front matter が要ります")
        }
        let raw: Any?
        do {
            raw = try Yams.load(yaml: split.yaml)
        } catch let e as YamlError {
            // Yams の mark は 0 始まりの行。front matter は 2 行目から始まる。
            let line = markLine(of: e).map { $0 + 2 }
            throw FrontMatterError(line: line, message: "YAML として読めません: \(e)")
        } catch {
            throw FrontMatterError(line: nil, message: "YAML として読めません: \(error)")
        }
        guard let dict = raw as? [String: Any] else {
            throw FrontMatterError(line: 2, message: "front matter は 鍵: 値 の並びで書きます")
        }
        guard let name = dict["名前"] as? String, !name.isEmpty else {
            throw FrontMatterError(line: line(of: "名前", in: split.yaml), message: "名前 がありません")
        }
        guard let category = dict["種別"] as? String, !category.isEmpty else {
            throw FrontMatterError(line: line(of: "種別", in: split.yaml), message: "種別 がありません")
        }
        var node = Node(name: name, kind: kind, category: category, from: 0, to: nil)
        node.body = split.body

        // 効力 は 期間 の言い換えなので、両方あると意味が決まらない。黙って片方を採らない。
        guard dict["期間"] == nil || dict["効力"] == nil else {
            throw FrontMatterError(line: line(of: "期間", in: split.yaml), message: "期間 と 効力 は同じ意味です。どちらか一方だけ書きます")
        }
        // 年 と 期間 も片方だけ。両方あると点の出来事か続くものかが決まらない。
        if dict["年"] != nil, let other = ["期間", "効力"].first(where: { dict[$0] != nil }) {
            throw FrontMatterError(line: line(of: "年", in: split.yaml), message: "年 と \(other) は同時に書けません。どちらか一方だけ書きます")
        }
        if let y = dict["年"] {
            guard let year = y as? Int else {
                throw FrontMatterError(line: line(of: "年", in: split.yaml), message: "年 の値は整数で書きます")
            }
            node.from = year; node.to = year; node.isPoint = true
        } else if let p = dict["期間"] ?? dict["効力"] {
            let key = dict["期間"] != nil ? "期間" : "効力"
            guard let pair = p as? [Any], pair.count == 2 else {
                throw FrontMatterError(line: line(of: key, in: split.yaml), message: "\(key) は [開始, 終了] の形で書きます")
            }
            guard let from = pair[0] as? Int, let to = yearOrPresent(pair[1]) else {
                throw FrontMatterError(line: line(of: key, in: split.yaml), message: "\(key) の値は整数か 現在 で書きます")
            }
            node.from = from; node.to = to
        } else {
            throw FrontMatterError(line: line(of: "期間", in: split.yaml), message: "期間 か 年 のどちらかが要ります")
        }

        if let a = dict["別名"] {
            node.aliases = try list(a, key: "別名", arity: 2,
                                    line: line(of: "別名", in: split.yaml)) { row in
                guard let from = row[0] as? Int, let n = row[1] as? String else { return nil }
                return Alias(from: from, name: n)
            }
        }
        if let p = dict["親"] {
            guard let parent = p as? String else {
                throw FrontMatterError(line: line(of: "親", in: split.yaml), message: "親 は保存名を一つ書きます")
            }
            node.parent = parent
        }
        if let r = dict["支配"] {
            node.rules = try list(r, key: "支配", arity: 3,
                                  line: line(of: "支配", in: split.yaml)) { row in
                guard let from = row[0] as? Int, let to = yearOrPresent(row[1]), let pol = row[2] as? String else { return nil }
                return Rule(from: from, to: to, polity: pol)
            }
        }
        if let l = dict["由来"] {
            node.lineages = try list(l, key: "由来", arity: 3,
                                     line: line(of: "由来", in: split.yaml)) { row in
                guard let y = row[0] as? Int, let k = row[1] as? String, let o = row[2] as? String else { return nil }
                return Lineage(year: y, kind: k, origin: o)
            }
        }
        if let m = dict["出来事"] {
            node.marks = try list(m, key: "出来事", arity: 2,
                                  line: line(of: "出来事", in: split.yaml)) { row in
                guard let y = row[0] as? Int, let label = row[1] as? String else { return nil }
                return Mark(year: y, label: label)
            }
        }
        return node
    }

    /// front matter の中でその鍵が書かれている行の、ファイル内の行番号（1 始まり）。
    /// **誤りに行番号を添えるためだけに使う。**見つからなければ front matter の先頭を指す。
    /// front matter は 1 行目の `---` の次から始まるので、`+ 2` する。
    static func line(of key: String, in yaml: String) -> Int {
        for (i, l) in yaml.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            var t = l.drop { $0 == " " }
            // 鍵は引用されていることがある（`"期間": 322`）。Yams は引用を外した鍵で
            // 辞書を作るので、こちらも外して比べないと行が見つからず 2 行目を指してしまう。
            if t.first == "\"" || t.first == "'" { t = t.dropFirst() }
            guard t.hasPrefix(key) else { continue }
            let rest = t.dropFirst(key.count).drop { $0 == "\"" || $0 == "'" }
            if rest.first == ":" { return i + 2 }
        }
        return 2
    }

    /// `現在` なら nil、整数ならその値、それ以外は .none（失敗）。
    /// 戻り値の外側の Optional が失敗、内側が「現在か年か」を表す。
    private static func yearOrPresent(_ v: Any) -> Int?? {
        if let i = v as? Int { return .some(i) }
        if let s = v as? String, s == "現在" { return .some(nil) }
        return nil
    }

    private static func list<T>(_ v: Any, key: String, arity: Int, line: Int,
                                _ make: ([Any]) -> T?) throws(FrontMatterError) -> [T] {
        guard let rows = v as? [Any] else {
            throw FrontMatterError(line: line, message: "\(key) は - [ ... ] の並びで書きます")
        }
        var out: [T] = []
        for row in rows {
            guard let r = row as? [Any], r.count == arity, let item = make(r) else {
                throw FrontMatterError(line: line, message: "\(key) の各行は \(arity) 個の値を [ ] で囲んで書きます")
            }
            out.append(item)
        }
        return out
    }

    /// parser と scanner だけが Mark を持つ。reader の三つ目の関連値は Int32 で行ではない。
    private static func markLine(of error: YamlError) -> Int? {
        switch error {
        case .parser(_, _, let mark, _): return mark.line
        case .scanner(_, _, let mark, _): return mark.line
        default: return nil
        }
    }
}
