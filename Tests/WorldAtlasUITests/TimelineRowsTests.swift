import Testing
import WorldAtlasCore
@testable import WorldAtlasStore
@testable import WorldAtlasUI

@Suite struct TimelineRowsTests {
    @Test func selectedNodeIsTheTopBandAndItsChildrenFollow() async throws {
        let s = try await TestVault.sample()
        let rows = Timeline.rows(s, selected: "場所/職人街.md", kind: .place, year: 500)
        #expect(rows.first?.path == "場所/職人街.md")
        #expect(rows.first?.isRoot == true)
        #expect(rows.dropFirst().map(\.path)
                == ["場所/鉄鎚亭.md", "場所/ヴォルフ鍛冶場.md", "場所/三日月書肆.md", "場所/新鉄鎚亭.md"])
        #expect(rows.dropFirst().allSatisfy { !$0.isRoot })
    }

    @Test func nothingSelectedShowsTheKindsRootsAndNoSelfBand() async throws {
        let s = try await TestVault.sample()
        let rows = Timeline.rows(s, selected: nil, kind: .place, year: 500)
        #expect(rows.allSatisfy { !$0.isRoot })
        #expect(Set(rows.map(\.path)) == ["場所/ヴェルダ本土.md", "場所/灰嶺.md", "場所/環海諸島.md"])
    }

    @Test func switchingTheRailAwayFromTheSelectionShowsThatKindsRoots() async throws {
        // 職人街を選んだまま「出来事」へ替えると、年表は出来事の直下に追随する（設計書 8.6）。
        let s = try await TestVault.sample()
        let rows = Timeline.rows(s, selected: "場所/職人街.md", kind: .event, year: 500)
        #expect(rows.allSatisfy { !$0.isRoot })
        #expect(Set(rows.map(\.path)) == Set(s.roots[.event] ?? []))
        // 型を戻せば元の根に戻る。選択そのものは捨てていない。
        let back = Timeline.rows(s, selected: "場所/職人街.md", kind: .place, year: 500)
        #expect(back.first?.path == "場所/職人街.md")
    }

    @Test func aVanishedSelectionFallsBackToTheRoots() async throws {
        let s = try await TestVault.sample()
        let gone = Timeline.rows(s, selected: "場所/もう無い.md", kind: .place, year: 500)
        let none = Timeline.rows(s, selected: nil, kind: .place, year: 500)
        #expect(gone.map(\.path) == none.map(\.path))
    }

    @Test func rowCarriesWhatTheCanvasNeedsToDraw() async throws {
        let s = try await TestVault.sample()
        let rows = Timeline.rows(s, selected: "場所/職人街.md", kind: .place, year: 500)
        let inn = try #require(rows.first { $0.path == "場所/鉄鎚亭.md" })
        #expect(inn.from == 322)
        #expect(inn.to == 588)
        #expect(!inn.isPoint)
        #expect(inn.marks.map(\.year) == [460, 588])
        #expect(inn.category == "宿")
    }

    @Test func nameIsResolvedAtTheYear() async throws {
        let s = try await TestVault.sample()
        func eldenName(at y: Int) throws -> String {
            let rows = Timeline.rows(s, selected: "場所/北ヴェルダ.md", kind: .place, year: y)
            return try #require(rows.first { $0.path == "場所/エルデン邑.md" }).name
        }
        #expect(try eldenName(at: 200) == "エルデン邑")
        #expect(try eldenName(at: 600) == "エルデン市")
    }

    @Test func renamesComeThroughForTheDiamonds() async throws {
        let s = try await TestVault.sample()
        let rows = Timeline.rows(s, selected: "場所/北ヴェルダ.md", kind: .place, year: 500)
        let town = try #require(rows.first { $0.path == "場所/エルデン邑.md" })
        #expect(town.renames.map(\.from) == [318, 501])
    }

    @Test func rulesAreInheritedFromTheNearestAncestorThatHasThem() async throws {
        // エルデン邑に 支配: は無い。親の北ヴェルダの三つを継ぐ（設計書 5 節）。
        let s = try await TestVault.sample()
        let rows = Timeline.rows(s, selected: "場所/北ヴェルダ.md", kind: .place, year: 500)
        let town = try #require(rows.first { $0.path == "場所/エルデン邑.md" })
        #expect(town.rules.map(\.polity) == ["ヴェルダ王国", "北ヴェルダ王国", "海都同盟"])
        // エルデン邑は 96 年から。継いだ支配も 96 年で切られる（1 年からではない）。
        #expect(town.rules.map(\.from) == [96, 412, 596])
        // 本人に書いてある節点は、自分のものをそのまま使う。
        #expect(rows.first?.rules.map(\.from) == [1, 412, 596])
    }

    @Test func inheritedRulesAreCutToTheRowsOwnLifetime() async throws {
        // 鉄鎚亭は 322–588。四代上の北ヴェルダから 1 年〜現在の支配を継ぐので、
        // 切らないと建つ前と焼けた後にも色帯が伸びる。
        let s = try await TestVault.sample()
        let rows = Timeline.rows(s, selected: "場所/職人街.md", kind: .place, year: 500)
        let inn = try #require(rows.first { $0.path == "場所/鉄鎚亭.md" })
        #expect(inn.rules.map(\.polity) == ["ヴェルダ王国", "北ヴェルダ王国"])
        #expect(inn.rules.map(\.from) == [322, 412])
        #expect(inn.rules.map(\.to) == [412, 588])
        // 596 年からの海都同盟は、鉄鎚亭が消えた後なので落ちる。
        #expect(!inn.rules.contains { $0.polity == "海都同盟" })
    }

    @Test func aRowThatOutlivesItsRulersKeepsTheOpenEnd() async throws {
        // 北ヴェルダ自身は現在まで続く。最後の支配の終わりは nil のまま。
        let s = try await TestVault.sample()
        let rows = Timeline.rows(s, selected: "場所/ヴェルダ本土.md", kind: .place, year: 500)
        let north = try #require(rows.first { $0.path == "場所/北ヴェルダ.md" })
        #expect(north.rules.count == 3)
        #expect(north.rules.last?.to == nil)
    }

    @Test func aNodeWithNoRulerAnywhereAboveItGetsNone() async throws {
        let s = try await TestVault.sample()
        #expect(Timeline.effectiveRules(s, path: "場所/もう無い.md").isEmpty)
    }

    @Test func polityColoursAreFixedByStartYearThenName() async throws {
        let s = try await TestVault.sample()
        let idx = Timeline.polityIndices(s)
        // 五つの勢力すべてに番号が付く。
        #expect(idx.count == (s.roots[.polity]?.count ?? 0) + s.nodes.values.filter { $0.kind == .polity && $0.parentPath != nil }.count)
        // 開始年の早いものが先に来る。索引の順ではない。
        let byIndex = idx.sorted { $0.value < $1.value }.map(\.key)
        let starts = byIndex.compactMap { s.node(savedName: $0)?.from }
        #expect(starts == starts.sorted())
    }

    @Test func polityIndicesAreStableAcrossRebuilds() async throws {
        let a = Timeline.polityIndices(try await TestVault.sample())
        let b = Timeline.polityIndices(try await TestVault.sample())
        #expect(a == b)
    }

    @Test func anEventKindHasNoChildrenSoOnlyItsOwnBand() async throws {
        let s = try await TestVault.sample()
        let path = try #require(s.roots[.event]?.first)
        let rows = Timeline.rows(s, selected: path, kind: .event, year: 500)
        #expect(rows.count == 1)
        #expect(rows[0].isRoot)
        #expect(rows[0].isPoint)
    }
}
