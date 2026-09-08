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

    @Test("勢力の支配は、支配している場所である。支配を継承した子孫の場所も含む")
    func polityRules() async throws {
        let s = try await sample()
        let g = Relations.of(s, path: try path(s, "北ヴェルダ王国"), year: 500)
        let names = try #require(g.first { $0.title == "この年の支配" }).nodes.map(\.name)
        // 北ヴェルダ 自身に加え、支配を継承した子孫の場所（エルデン邑・職人街など）も出る——
        // 場所→勢力の向き（`rulers(of:at:)`）が継承込みで答えるのと同じ資格判定を、
        // 勢力→場所の向きにも通したことによる。
        #expect(names.contains("北ヴェルダ"))
        #expect(names.contains("王都エルデン"))
        #expect(names.contains("職人街"))
    }

    @Test("継承した支配は、両方向から見て一致する")
    func rulesAgreeInBothDirections() async throws {
        let s = try await sample()
        // 職人街 は自分自身に 支配 を持たず、エルデン邑 を経て 北ヴェルダ から継承する
        // （場所→勢力の向きは元々これを拾う）。逆向きが同じ関数を通るなら、
        // 北ヴェルダ王国 の一覧にも 職人街 が出るはずである。
        let workshop = Relations.of(s, path: try path(s, "職人街"), year: 500)
        let workshopRules = try #require(workshop.first { $0.title == "この年の支配" }).nodes.map(\.name)
        #expect(workshopRules == ["北ヴェルダ王国"])

        let kingdom = Relations.of(s, path: try path(s, "北ヴェルダ王国"), year: 500)
        let kingdomRules = try #require(kingdom.first { $0.title == "この年の支配" }).nodes.map(\.name)
        #expect(kingdomRules.contains("職人街"))
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

    @Test("参照しているは、本文のリンク先である。その年の呼び名で出る")
    func outgoingRefs() async throws {
        let s = try await sample()
        let g = Relations.of(s, path: try path(s, "北ヴェルダ王国"), year: 500)
        let refs = try #require(g.first { $0.title == "参照している" })
        // 北ヴェルダ王国 の本文は [[エルデン邑]] を指す。500 年の呼び名は 王都エルデン。
        #expect(refs.nodes.map(\.name).contains("王都エルデン"))
    }

    @Test("支配の逆走査は境界年で切り替わる。596 年ちょうどは海都同盟の側")
    func rulesReverseScanBoundary() async throws {
        let s = try await sample()
        let northVerda = try path(s, "北ヴェルダ")

        let old = Relations.of(s, path: try path(s, "北ヴェルダ王国"), year: 596)
        let oldNames = old.first { $0.title == "この年の支配" }?.nodes.map(\.path) ?? []
        #expect(!oldNames.contains(northVerda))   // 区間は [412, 596) で閉じている

        let new = Relations.of(s, path: try path(s, "海都同盟"), year: 596)
        let newRow = try #require(new.first { $0.title == "この年の支配" }).nodes
            .first { $0.path == northVerda }
        #expect(newRow?.name == "北ヴェルダ")
    }

    @Test("互いに由来を書き合う二つの節点でも、同じ行が二重に出ない")
    func mutualLineage() async throws {
        let s = try await TestVault.snapshot([
            "勢力/甲.md": """
            ---
            名前: 甲
            種別: 勢力
            期間: [1, 現在]
            由来:
              - [100, 分離, 乙]
            ---
            """,
            "勢力/乙.md": """
            ---
            名前: 乙
            種別: 勢力
            期間: [1, 現在]
            由来:
              - [100, 分離, 甲]
            ---
            """,
        ])
        let p = try #require(s.path(ofSavedName: "甲"))
        let g = Relations.of(s, path: p, year: 200)
        let rows = try #require(g.first { $0.title == "繋がり" }).nodes
        // 甲 自身の 由来 と、乙 の 由来 の逆向きから、同じ (path, note) が二度来る。
        #expect(rows.count == 1)
        #expect(Set(rows.map(\.id)).count == rows.count)
    }

    @Test("同じ節点へ別々の由来があるときは、二行とも残る")
    func twoFactsSameNode() async throws {
        let s = try await TestVault.snapshot([
            "勢力/甲.md": """
            ---
            名前: 甲
            種別: 勢力
            期間: [1, 現在]
            由来:
              - [100, 分離, 乙]
            ---
            """,
            "勢力/乙.md": """
            ---
            名前: 乙
            種別: 勢力
            期間: [1, 現在]
            由来:
              - [200, 統合, 甲]
            ---
            """,
        ])
        let p = try #require(s.path(ofSavedName: "甲"))
        let g = Relations.of(s, path: p, year: 300)
        let rows = try #require(g.first { $0.title == "繋がり" }).nodes
        // 甲 自身の 由来（100 分離）と、乙 の 由来 の逆向き（200 統合）。別々の事実である。
        #expect(rows.count == 2)
        #expect(rows.map(\.note).sorted() == ["100 分離", "200 統合"])
        #expect(Set(rows.map(\.id)).count == 2)
        // 自分の 由来 が先に来る（設計書 8.4 の順）。
        #expect(rows.first?.note == "100 分離")
    }

    @Test("空の組は出さない")
    func skipsEmpty() async throws {
        let s = try await sample()
        let g = Relations.of(s, path: try path(s, "ヴェルダの分裂"), year: 412)
        #expect(!g.contains { $0.nodes.isEmpty })
    }

    @Test("同じ節点を保存名と別名の両方でリンクしても、参照されているは一行にまとまる")
    func backrefsDedupAcrossAliasLinks() async throws {
        let s = try await TestVault.snapshot([
            "場所/的.md": """
            ---
            名前: 的
            種別: 都市
            期間: [1, 現在]
            別名:
              - [50, 別名的]
            ---
            """,
            "場所/元.md": """
            ---
            名前: 元
            種別: 区
            期間: [1, 現在]
            ---
            [[的]] と、後で改名した [[別名的]] の両方を書く。同じ節点を指している。
            """,
        ])
        let p = try #require(s.path(ofSavedName: "的"))
        let g = Relations.of(s, path: p, year: 100)
        let back = try #require(g.first { $0.title == "参照されている" })
        #expect(back.nodes.count == 1)
        #expect(Set(back.nodes.map(\.id)).count == back.nodes.count)
    }

    @Test("知らない path では空を返す")
    func unknown() async throws {
        let s = try await sample()
        #expect(Relations.of(s, path: "場所/無い.md", year: 500).isEmpty)
    }
}
