import Foundation
import Testing
import WorldAtlasCore
import WorldAtlasStore
@testable import WorldAtlasUI

@Suite("関連の四種")
struct RelationsTests {
    /// 見本を索引して snapshot を得る。**複製を索引する**——見本は固定資料である。
    private func sample() async throws -> Snapshot {
        try await TestVault.sample()
    }

    private func path(_ s: Snapshot, _ savedName: String) throws -> String {
        try #require(s.path(ofSavedName: savedName))
    }

    @Test("北ヴェルダ王国の 500 年。組は設計書 8.4 の順で出る")
    func groups() async throws {
        let s = try await sample()
        let g = Relations.of(s, path: try path(s, "北ヴェルダ王国"), year: 500)
        let order = ["繋がり", "この年の支配", "参照している", "参照されている"]
        // 出た組が、8.4 の順に並んでいること（無い組は飛ばしてよい）。
        #expect(g.map(\.title) == order.filter { t in g.contains { $0.title == t } })
    }

    @Test("繋がりは由来の両方向。412 に分かれ、596 に統合される")
    func lineages() async throws {
        let s = try await sample()
        let g = Relations.of(s, path: try path(s, "北ヴェルダ王国"), year: 500)
        let names = try #require(g.first { $0.title == "繋がり" }).nodes.map(\.name)
        #expect(names.contains("ヴェルダ帝国"))     // 自分の 由来 に書いてある側（210 年に改称、500 年の呼び名）
        #expect(names.contains("海都同盟"))         // 相手の 由来 に自分が書かれている側
    }

    @Test("勢力の支配は、支配している場所である")
    func polityRules() async throws {
        let s = try await sample()
        let g = Relations.of(s, path: try path(s, "北ヴェルダ王国"), year: 500)
        let names = try #require(g.first { $0.title == "この年の支配" }).nodes.map(\.name)
        #expect(names == ["北ヴェルダ"])
    }

    @Test("場所の支配は、支配している勢力である")
    func placeRulers() async throws {
        let s = try await sample()
        let g = Relations.of(s, path: try path(s, "北ヴェルダ"), year: 500)
        let names = try #require(g.first { $0.title == "この年の支配" }).nodes.map(\.name)
        #expect(names == ["北ヴェルダ王国"])
    }

    @Test("支配は年で変わる。596 年以降は海都同盟の側になる")
    func rulersChange() async throws {
        let s = try await sample()
        let g = Relations.of(s, path: try path(s, "北ヴェルダ"), year: 650)
        let names = try #require(g.first { $0.title == "この年の支配" }).nodes.map(\.name)
        #expect(names == ["環海連合"])   // 596 年に改称している。呼び名は年で解く
    }

    @Test("その年に存在しない節点は absent が立つ")
    func absent() async throws {
        let s = try await sample()
        let g = Relations.of(s, path: try path(s, "北ヴェルダ王国"), year: 500)
        let back = try #require(g.first { $0.title == "参照されている" })
        let split = try #require(back.nodes.first { $0.name == "ヴェルダの分裂" })
        #expect(split.absent)          // 412 年の点の出来事。500 年には居ない
        let law = try #require(back.nodes.first { $0.name == "継承法" })
        #expect(!law.absent)
    }

    @Test("名前はその年の呼び名で出る")
    func displayName() async throws {
        let s = try await sample()
        let g = Relations.of(s, path: try path(s, "北ヴェルダ"), year: 700)
        let names = g.flatMap { $0.nodes.map(\.name) }
        #expect(names.contains("環海連合"))
        #expect(!names.contains("海都同盟"))
    }

    @Test("空の組は出さない")
    func skipsEmpty() async throws {
        let s = try await sample()
        let g = Relations.of(s, path: try path(s, "ヴェルダの分裂"), year: 412)
        #expect(!g.contains { $0.nodes.isEmpty })
    }

    @Test("知らない path では空を返す")
    func unknown() async throws {
        let s = try await sample()
        #expect(Relations.of(s, path: "場所/無い.md", year: 500).isEmpty)
    }
}
