import Foundation
import Yams

public struct CalendarDef: Equatable, Sendable, Codable {
    public var name: String
    /// 基準暦の年に足す数。
    public var offset: Int
    public init(name: String, offset: Int) { self.name = name; self.offset = offset }

    /// 基準暦の年をこの暦で表す。0 以下は「前 n 年」。
    public func format(_ baseYear: Int) -> String {
        let v = baseYear + offset
        return v > 0 ? "\(name) \(v) 年" : "\(name)前 \(1 - v) 年"
    }
}

public struct World: Equatable, Sendable, Codable {
    public var name: String
    public var baseCalendar: String
    public var calendars: [CalendarDef]
    /// 年カーソルの位置。基準暦の年。
    public var current: Int
    public init(name: String, baseCalendar: String, calendars: [CalendarDef], current: Int) {
        self.name = name; self.baseCalendar = baseCalendar; self.calendars = calendars; self.current = current
    }
}

public enum WorldFile {
    public static func parse(_ yaml: String) throws(FrontMatterError) -> World {
        let raw: Any?
        do { raw = try Yams.load(yaml: yaml) } catch {
            throw FrontMatterError(line: nil, message: "世界.yaml が YAML として読めません: \(error)")
        }
        guard let d = raw as? [String: Any] else {
            throw FrontMatterError(line: nil, message: "世界.yaml は 鍵: 値 の並びで書きます")
        }
        guard let name = d["名前"] as? String, !name.isEmpty else {
            throw FrontMatterError(line: nil, message: "名前 がありません")
        }
        guard let base = d["基準暦"] as? String else {
            throw FrontMatterError(line: nil, message: "基準暦 がありません")
        }
        guard let rows = d["暦"] as? [Any], !rows.isEmpty else {
            throw FrontMatterError(line: nil, message: "暦 は - [名前, 加算する数] の並びで書きます")
        }
        var cals: [CalendarDef] = []
        for row in rows {
            guard let r = row as? [Any], r.count == 2, let n = r[0] as? String, let off = r[1] as? Int else {
                throw FrontMatterError(line: nil, message: "暦 の各行は [名前, 加算する数] で書きます")
            }
            cals.append(CalendarDef(name: n, offset: off))
        }
        guard cals.contains(where: { $0.name == base }) else {
            throw FrontMatterError(line: nil, message: "基準暦 が 暦 の一覧にありません")
        }
        guard let current = d["現在"] as? Int else {
            throw FrontMatterError(line: nil, message: "現在 は整数で書きます")
        }
        return World(name: name, baseCalendar: base, calendars: cals, current: current)
    }

    /// 人が読める並びで書き出す。Yams の dump は鍵の順を保たないので手で組む。
    public static func render(_ w: World) -> String {
        var s = "名前: \(scalar(w.name))\n基準暦: \(scalar(w.baseCalendar))\n暦:\n"
        for c in w.calendars { s += "  - [\(scalar(c.name, flow: true)), \(c.offset)]\n" }
        s += "現在: \(w.current)\n"
        return s
    }

    /// 値を YAML の一行の形にする。平文で書けるかどうかの判断は Yams に任せ、書けない値は
    /// Yams に引用させる。flow が真なら `[ ]` の中に置く値で、そこでは `, [ ] { }` も区切りに
    /// なるが Yams は block の文脈で見るので、その分だけこちらで引用に落とす。
    private static func scalar(_ s: String, flow: Bool = false) -> String {
        guard let d = try? Yams.dump(object: s, allowUnicode: true).trimmingCharacters(in: .newlines),
              !d.contains("\n") else { return quoted(s) }
        let isPlain = d.first != "'" && d.first != "\""
        if flow, isPlain, d.contains(where: { ",[]{}".contains($0) }) { return quoted(s) }
        return d
    }

    /// どの文脈でも一行に収まる二重引用符の形。複数行になる値と dump の失敗はここへ落とす。
    private static func quoted(_ s: String) -> String {
        var e = ""
        for c in s {
            switch c {
            case "\\": e += "\\\\"
            case "\"": e += "\\\""
            case "\n": e += "\\n"
            default: e.append(c)
            }
        }
        return "\"\(e)\""
    }
}
