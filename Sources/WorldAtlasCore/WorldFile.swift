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
        var s = "名前: \(w.name)\n基準暦: \(w.baseCalendar)\n暦:\n"
        for c in w.calendars { s += "  - [\(c.name), \(c.offset)]\n" }
        s += "現在: \(w.current)\n"
        return s
    }
}
