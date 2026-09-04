import Foundation

public enum WikiLinks {
    // Regex は Sendable ではないが、リテラルから作った不変値で読み取り専用。共有しても安全。
    nonisolated(unsafe) private static let pattern: Regex<(Substring, Substring)> = /\[\[([^\[\]]+?)\]\]/

    public struct Count: Equatable, Sendable {
        public var target: String
        public var count: Int
    }

    /// 本文の [[…]] を最初の出現順に、回数つきで返す。前後の空白は落とす。
    public static func counts(in body: String) -> [Count] {
        var index: [String: Int] = [:]
        var out: [Count] = []
        for m in body.matches(of: pattern) {
            let t = String(m.1).trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }
            if let i = index[t] { out[i].count += 1 } else { index[t] = out.count; out.append(Count(target: t, count: 1)) }
        }
        return out
    }

    /// 本文の [[…]] を出現順に、重複を除いて返す。
    public static func targets(in body: String) -> [String] {
        counts(in: body).map(\.target)
    }
}
