import Testing
@testable import WorldAtlasUI

@Suite struct TimelineTicksTests {
    @Test func candidatesAreTheEightFromTheSpec() {
        #expect(TimelineTicks.candidates == [5, 10, 20, 25, 50, 100, 200, 500])
    }

    @Test func picksTheFinestThatKeepsTheGap() {
        // 1 年 = 20 点なら、5 年ごとで 100 点。64 点の下限を超えるので 5 年で足りる。
        #expect(TimelineTicks.interval(pxPerYear: 20, minGap: 64) == 5)
        // 1 年 = 2 点なら 5 年で 10 点しかない。64 点を超えるのは 50 年（100 点）から。
        #expect(TimelineTicks.interval(pxPerYear: 2, minGap: 64) == 50)
        // 1 年 = 0.1 点。500 年でも 50 点しかないが、候補の最大で打ち止める。
        #expect(TimelineTicks.interval(pxPerYear: 0.1, minGap: 64) == 500)
    }

    @Test func neverReturnsAValueOutsideTheCandidates() {
        for p in stride(from: 0.01, through: 40, by: 0.13) {
            #expect(TimelineTicks.candidates.contains(TimelineTicks.interval(pxPerYear: p)))
        }
    }

    @Test func yearsAreTheMultiplesInsideTheSpan() {
        #expect(TimelineTicks.years(in: 96...212, interval: 50) == [100, 150, 200])
    }

    @Test func spanEndsExactlyOnAMultiple() {
        // 端がちょうど目盛りに乗るときは、その目盛りを含める。
        #expect(TimelineTicks.years(in: 100...200, interval: 50) == [100, 150, 200])
    }

    @Test func negativeYearsGetTicksToo() {
        // 0 以下の年は「前 n 年」と表す（設計書 6 節）。目盛り自体は普通に並ぶ。
        #expect(TimelineTicks.years(in: -30...30, interval: 20) == [-20, 0, 20])
    }

    @Test func aSpanNarrowerThanOneIntervalCanBeEmpty() {
        #expect(TimelineTicks.years(in: 101...149, interval: 50).isEmpty)
    }
}
