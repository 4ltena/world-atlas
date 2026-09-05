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
        // 同じ周期にすると、六つ目で色も模様も 0 番と同じになる。
        func pair(_ i: Int) -> String { "\(Palette.polity(i))/\(Palette.polityDash(i))" }
        #expect(Set((0..<20).map(pair)).count == 20)
        #expect(pair(20) == pair(0))   // 21 個目でようやく一周する
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
