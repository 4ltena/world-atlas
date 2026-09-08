import Foundation
import Testing
import WorldAtlasCore
import WorldAtlasStore
@testable import WorldAtlasUI

@Suite("探した名前が今の年に無いとき")
struct ArrivalTests {
    private func path(_ s: Snapshot, _ savedName: String) throws -> String {
        try #require(s.path(ofSavedName: savedName))
    }
    private let cal = CalendarDef(name: "帝国暦", offset: 0)

    @Test("別名で辿り着くと、その名前の期間を言う")
    func alias() async throws {
        let s = try await TestVault.sample()
        let a = try #require(ArrivalNotice.make(s, path: try path(s, "エルデン邑"), year: 500,
                                                arrivedAs: "エルデン市", calendar: cal))
        #expect(a.message.contains("エルデン市"))
        #expect(a.message.contains("501"))
    }

    @Test("終わりが現在の名前は、世界の端で閉じて真ん中を採る")
    func openEnded() async throws {
        let s = try await TestVault.sample()
        let a = try #require(ArrivalNotice.make(s, path: try path(s, "エルデン邑"), year: 500,
                                                arrivedAs: "エルデン市", calendar: cal))
        #expect(a.year == ArrivalNotice.middle(from: 501, to: s.extent.hi))
    }

    @Test("真ん中は下へ丸める")
    func floors() {
        #expect(ArrivalNotice.middle(from: 501, to: 712) == 606)   // 606.5 → 606
        #expect(ArrivalNotice.middle(from: 100, to: 101) == 100)
    }

    @Test("負の年でも下へ丸める。Swift の / は 0 の側へ丸めるので、そのままでは食い違う")
    func floorsNegative() {
        #expect(ArrivalNotice.middle(from: -10, to: -3) == -7)     // -6.5 → -7
        #expect(ArrivalNotice.middle(from: -5, to: 4) == -1)       // -0.5 → -1
    }

    @Test("今の年の呼び名で辿り着いたなら、何も出さない")
    func sameName() async throws {
        let s = try await TestVault.sample()
        #expect(ArrivalNotice.make(s, path: try path(s, "エルデン邑"), year: 400,
                                   arrivedAs: "王都エルデン", calendar: cal) == nil)
    }

    @Test("期間の中にいるなら、何も出さない")
    func inside() async throws {
        let s = try await TestVault.sample()
        #expect(ArrivalNotice.make(s, path: try path(s, "エルデン邑"), year: 600,
                                   arrivedAs: "エルデン市", calendar: cal) == nil)
    }

    @Test("辿り着いた名前が無くても、その年に存在しなければ言う")
    func absent() async throws {
        let s = try await TestVault.sample()
        let a = try #require(ArrivalNotice.make(s, path: try path(s, "北ヴェルダ王国"), year: 700,
                                                arrivedAs: nil, calendar: cal))
        #expect(a.message.contains("412"))
        #expect(a.message.contains("596"))
        #expect(a.year == 504)                                     // (412+596)/2
    }

    @Test("点の出来事は、その一年を言う")
    func point() async throws {
        let s = try await TestVault.sample()
        let a = try #require(ArrivalNotice.make(s, path: try path(s, "ヴェルダの分裂"), year: 500,
                                                arrivedAs: nil, calendar: cal))
        #expect(a.year == 412)
    }

    @Test("両方成り立つときは、辿り着いた名前のほうを言う")
    func bothCases() async throws {
        let s = try await TestVault.sample()
        let a = try #require(ArrivalNotice.make(s, path: try path(s, "北ヴェルダ王国"), year: 700,
                                                arrivedAs: "北ヴェルダ共和国", calendar: cal))
        #expect(a.message.contains("北ヴェルダ共和国"))
        #expect(a.year == ArrivalNotice.middle(from: 501, to: 596))
    }

    @Test("存在していて名前も合っているなら、何も出さない")
    func nothing() async throws {
        let s = try await TestVault.sample()
        #expect(ArrivalNotice.make(s, path: try path(s, "北ヴェルダ王国"), year: 450,
                                   arrivedAs: nil, calendar: cal) == nil)
    }

    @Test("知らない path では何も出さない")
    func unknown() async throws {
        let s = try await TestVault.sample()
        #expect(ArrivalNotice.make(s, path: "場所/無い.md", year: 500,
                                   arrivedAs: "何か", calendar: cal) == nil)
    }

    @Test("暦の加算値が効く。聖暦なら 96 を引いた数で出る")
    func calendarOffset() async throws {
        let s = try await TestVault.sample()
        let a = try #require(ArrivalNotice.make(s, path: try path(s, "エルデン邑"), year: 500,
                                                arrivedAs: "エルデン市",
                                                calendar: CalendarDef(name: "聖暦", offset: -96)))
        #expect(a.message.contains("405"))       // 501 - 96
        // **移る先は基準暦のままである。**`setYear` が受けるのは基準暦の年である。
        #expect(a.year == ArrivalNotice.middle(from: 501, to: s.extent.hi))
    }
}
