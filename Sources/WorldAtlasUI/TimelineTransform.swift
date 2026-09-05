import Foundation
import WorldAtlasCore

/// 年と横座標の変換。年表は x だけが伸縮し、y は行の固定送りである（設計書 8.6）。
/// 変換は描画の計算に畳んで使う。`.scaleEffect` に戻すと帯や線まで太る。
public struct TimelineTransform: Equatable, Sendable {
    /// 画面の左端に来る年。掴んで動かす途中は端数になる。
    public var origin: Double
    /// 1 年あたりの点数。
    public var pxPerYear: Double
    /// 描画領域の幅。
    public var width: Double

    /// これ以上は寄れない（設計書 8.6）。
    public static let minimumYears = 12.0
    /// 行が狭いときに広げる幅（設計書 8.6）。
    public static let narrowFit = 40.0

    public init(origin: Double, pxPerYear: Double, width: Double) {
        self.origin = origin
        self.pxPerYear = pxPerYear
        self.width = width
    }

    /// 画面に入っている年数。
    public var years: Double { width / pxPerYear }

    public func x(of year: Double) -> Double { (year - origin) * pxPerYear }
    public func year(atX x: Double) -> Double { origin + x / pxPerYear }

    /// 世界の端。年カーソルは右端の 10 年先まで動けるので、そこまでを世界とする（設計書 6 節）。
    static func bounds(_ limits: Extent) -> ClosedRange<Double> {
        Double(limits.lo)...Double(limits.hi + 10)
    }

    /// アンカーの下にある年を動かさずに倍率を変える。
    public func zoomed(by factor: Double, aroundX anchor: Double, limits: Extent) -> Self {
        let b = Self.bounds(limits)
        let worldYears = b.upperBound - b.lowerBound
        let held = year(atX: anchor)
        let wanted = years / factor
        let clamped = min(max(wanted, Self.minimumYears), max(worldYears, Self.minimumYears))
        var t = self
        t.pxPerYear = width / clamped
        t.origin = held - anchor / t.pxPerYear
        return t.clampedToBounds(limits)
    }

    /// 横に引く。掴んで動かす向きに合わせ、正の dx は過去へ戻る。
    public func panned(byX dx: Double, limits: Extent) -> Self {
        var t = self
        t.origin -= dx / pxPerYear
        return t.clampedToBounds(limits)
    }

    /// 見える範囲を世界の端の中へ収める。世界より広い倍率のときは世界を中央に置く。
    func clampedToBounds(_ limits: Extent) -> Self {
        let b = Self.bounds(limits)
        let worldYears = b.upperBound - b.lowerBound
        var t = self
        if years >= worldYears {
            t.origin = b.lowerBound - (years - worldYears) / 2
        } else {
            t.origin = min(max(origin, b.lowerBound), b.upperBound - years)
        }
        return t
    }

    /// 年の範囲を画面へ当てはめる。40 年未満の行は、その中心のまわりに 40 年へ広げる。
    /// **広げた結果が世界より広くなってはいけない**（設計書 8.6 の上限は世界の全体）。
    public static func fitting(_ range: ClosedRange<Int>, width: Double, limits: Extent) -> Self {
        let lo = Double(range.lowerBound), hi = Double(range.upperBound)
        let b = bounds(limits)
        let worldYears = b.upperBound - b.lowerBound
        var span = hi - lo
        var start = lo
        if span < narrowFit {
            let middle = (lo + hi) / 2
            span = min(narrowFit, max(worldYears, minimumYears))
            start = middle - span / 2
        }
        span = max(span, minimumYears)
        return Self(origin: start, pxPerYear: width / span, width: width).clampedToBounds(limits)
    }

    /// 覚えていた年の範囲を、いまの幅で出し直す。**`fitting` と違って広げない。**
    /// 40 年未満へ寄せた尺を覚えて開き直したとき、勝手に 40 年へ戻っては困る。
    /// **世界より広い範囲が覚えられていることがある**（節点を消して世界が縮んだ後）。
    /// 上限は世界の全体である（設計書 8.6）。
    public static func showing(_ range: ClosedRange<Int>, width: Double, limits: Extent) -> Self {
        let b = bounds(limits)
        let worldYears = b.upperBound - b.lowerBound
        let lo = Double(range.lowerBound)
        var span = max(Double(range.upperBound) - lo, minimumYears)
        span = min(span, max(worldYears, minimumYears))
        return Self(origin: lo, pxPerYear: width / span, width: width).clampedToBounds(limits)
    }

    /// 世界の全体を出す。
    public static func whole(width: Double, limits: Extent) -> Self {
        let b = bounds(limits)
        let span = max(b.upperBound - b.lowerBound, minimumYears)
        return Self(origin: b.lowerBound, pxPerYear: width / span, width: width).clampedToBounds(limits)
    }
}
