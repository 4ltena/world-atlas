import Foundation

/// 年表の目盛り。間隔は設計書 8.6 の八つの候補からだけ選ぶ。
public enum TimelineTicks {
    public static let candidates = [5, 10, 20, 25, 50, 100, 200, 500]

    /// 目盛りどうしが minGap 点より近づかない、いちばん細かい間隔。
    /// どれも足りなければ、いちばん粗いもので打ち止める。
    public static func interval(pxPerYear: Double, minGap: Double = 64) -> Int {
        candidates.first { Double($0) * pxPerYear >= minGap } ?? candidates[candidates.count - 1]
    }

    /// 見えている範囲に入る目盛りの年。
    public static func years(in span: ClosedRange<Double>, interval: Int) -> [Int] {
        guard interval > 0 else { return [] }
        let step = Double(interval)
        var y = (span.lowerBound / step).rounded(.up) * step
        var out: [Int] = []
        while y <= span.upperBound {
            out.append(Int(y.rounded()))
            y += step
        }
        return out
    }
}
