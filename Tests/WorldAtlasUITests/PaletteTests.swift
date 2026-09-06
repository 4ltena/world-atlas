import SwiftUI
import Testing
@testable import WorldAtlasUI

@Suite @MainActor struct PaletteTests {
    @Test func fiveColoursAndFourPatterns() {
        #expect(Palette.polityCount == 5)
        #expect(Palette.polityDashCount == 4)
        // 四つとも別の模様である。色が近くても模様で分かれる。
        let dashes = (0..<4).map { Palette.polityDash($0) }
        #expect(Set(dashes.map(\.description)).count == 4)
    }

    @Test func indexWrapsRatherThanCrashing() {
        // 勢力が六つ以上になっても落ちない。色は 5、模様は 4 で巡回する。
        #expect(Palette.polity(5) == Palette.polity(0))
        #expect(Palette.polityDash(5) == Palette.polityDash(1))
    }

    @Test func twentyPolitiesAreAllDistinguishable() {
        // 5 と 4 は互いに素なので、色と模様の組は 20 まで重ならない。
        // **文字列にして比べない。**Color の description にはインスタンスごとの UUID が入るので、
        // 五色が全部同じ値でも「別物」に見えてしまう。値で比べる。
        for i in 0..<20 {
            for j in (i + 1)..<20 {
                #expect(!(Palette.polity(i) == Palette.polity(j)
                          && Palette.polityDash(i) == Palette.polityDash(j)))
            }
        }
        #expect(Palette.polity(20) == Palette.polity(0))        // 21 個目でようやく一周する
        #expect(Palette.polityDash(20) == Palette.polityDash(0))
    }

    @Test func theFiveColoursAreAllDifferentValues() {
        // 設計書 10 節は五色を検証器で選んだ値だと定めている。同じ値が混ざっていないこと。
        for i in 0..<5 {
            for j in (i + 1)..<5 {
                #expect(Palette.polity(i) != Palette.polity(j))
            }
        }
    }

    @Test func negativeIndexIsSafe() {
        #expect(Palette.polity(-1) == Palette.polity(4))
        #expect(Palette.polityDash(-1) == Palette.polityDash(3))
    }

    @Test func firstDashIsSolid() {
        // いちばん多く出る勢力が実線になるよう、0 番は模様なしにする。
        #expect(Palette.polityDash(0).isEmpty)
    }
}
