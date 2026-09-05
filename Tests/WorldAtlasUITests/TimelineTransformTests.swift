import Testing
import WorldAtlasCore
@testable import WorldAtlasUI

@Suite struct TimelineTransformTests {
    let world = Extent(lo: 1, hi: 712)   // 見本の vault と同じ端

    @Test func yearAndXAreInverses() {
        let t = TimelineTransform(origin: 100, pxPerYear: 2, width: 800)
        #expect(t.x(of: 100) == 0)
        #expect(t.x(of: 200) == 200)
        #expect(t.year(atX: 200) == 200)
        #expect(t.year(atX: t.x(of: 345.5)) == 345.5)
    }

    @Test func yearsIsTheVisibleSpan() {
        #expect(TimelineTransform(origin: 0, pxPerYear: 2, width: 800).years == 400)
    }

    @Test func zoomKeepsTheYearUnderTheAnchor() {
        let t = TimelineTransform(origin: 100, pxPerYear: 2, width: 800)
        let anchor = 300.0
        let before = t.year(atX: anchor)
        let z = t.zoomed(by: 2, aroundX: anchor, limits: world)
        #expect(abs(z.year(atX: anchor) - before) < 0.001)
        #expect(z.pxPerYear == 4)
    }

    @Test func zoomStopsAtTwelveYears() {
        // 下限は 12 年（設計書 8.6）。これ以上は寄れない。
        var t = TimelineTransform(origin: 300, pxPerYear: 2, width: 600)
        for _ in 0..<20 { t = t.zoomed(by: 2, aroundX: 300, limits: world) }
        #expect(abs(t.years - TimelineTransform.minimumYears) < 0.001)
    }

    @Test func zoomStopsAtTheWholeWorld() {
        // 上限は世界の全体。年カーソルは右端の 10 年先まで動けるので、そこまでを世界とする。
        var t = TimelineTransform(origin: 300, pxPerYear: 2, width: 600)
        for _ in 0..<20 { t = t.zoomed(by: 0.5, aroundX: 300, limits: world) }
        #expect(abs(t.years - Double(world.hi + 10 - world.lo)) < 0.001)
    }

    @Test func panStopsAtTheEdges() {
        let t = TimelineTransform.fitting(300...400, width: 800, limits: world)
        let left = t.panned(byX: 100_000, limits: world)
        #expect(abs(left.origin - Double(world.lo)) < 0.001)
        let right = t.panned(byX: -100_000, limits: world)
        #expect(abs(right.origin + right.years - Double(world.hi + 10)) < 0.001)
    }

    @Test func fittingUsesTheRangeWhenItIsWideEnough() {
        let t = TimelineTransform.fitting(200...600, width: 800, limits: world)
        #expect(abs(t.origin - 200) < 0.001)
        #expect(abs(t.years - 400) < 0.001)
    }

    @Test func fittingWidensANarrowRangeAroundItsMiddle() {
        // 322–588 は 266 年で広い。鉄鎚亭のような短い行は 40 年まで広げる。
        let t = TimelineTransform.fitting(500...510, width: 800, limits: world)
        #expect(abs(t.years - 40) < 0.001)
        #expect(abs(t.origin + t.years / 2 - 505) < 0.001)
    }

    @Test func fittingAPointYearStillGivesFortyYears() {
        let t = TimelineTransform.fitting(588...588, width: 800, limits: world)
        #expect(abs(t.years - 40) < 0.001)
    }

    @Test func fittingNeverGoesWiderThanTheWorld() {
        // 節点が少ない vault では世界が 40 年より狭い。40 年へ広げてはいけない
        // （設計書 8.6 の上限は世界の全体である）。
        let tiny = Extent(lo: 1, hi: 3)          // 端は 1...13 の 12 年
        let t = TimelineTransform.fitting(1...3, width: 800, limits: tiny)
        #expect(abs(t.years - 12) < 0.001)
        #expect(abs(t.origin - 1) < 0.001)
    }

    @Test func showingRestoresARangeWithoutWideningIt() {
        // 覚えていた尺を戻すときは広げない。fitting は 40 年未満を広げるので使えない。
        let t = TimelineTransform.showing(300...312, width: 800, limits: world)
        #expect(abs(t.origin - 300) < 0.001)
        #expect(abs(t.years - 12) < 0.001)
    }

    @Test func showingNeverGoesWiderThanTheWorld() {
        // 節点を消して世界が縮んだあと、前の広い尺が覚えられていることがある。
        let tiny = Extent(lo: 1, hi: 3)          // 端は 1...13 の 12 年
        let t = TimelineTransform.showing(1...400, width: 800, limits: tiny)
        #expect(abs(t.years - 12) < 0.001)
    }

    @Test func showingStillRespectsTheMinimum() {
        // 12 年より狭い範囲が覚えられていても、寄れる下限は守る。
        let t = TimelineTransform.showing(300...304, width: 800, limits: world)
        #expect(abs(t.years - TimelineTransform.minimumYears) < 0.001)
    }

    @Test func wholeShowsTheWholeWorld() {
        let t = TimelineTransform.whole(width: 800, limits: world)
        #expect(abs(t.origin - Double(world.lo)) < 0.001)
        #expect(abs(t.years - Double(world.hi + 10 - world.lo)) < 0.001)
    }

    @Test func aWorldNarrowerThanTheMinimumIsCentred() {
        // まだ節点が少ない vault では、世界が 12 年より狭いことがある。
        let tiny = Extent(lo: 1, hi: 3)
        let t = TimelineTransform.whole(width: 800, limits: tiny)
        #expect(t.years >= TimelineTransform.minimumYears)
        let middle = t.origin + t.years / 2
        #expect(abs(middle - Double(tiny.lo + tiny.hi + 10) / 2) < 0.001)
    }
}
