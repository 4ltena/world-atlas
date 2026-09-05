import Testing
import WorldAtlasCore
@testable import WorldAtlasStore
@testable import WorldAtlasUI

@Suite struct ManuscriptTests {
    let imperial = CalendarDef(name: "帝国暦", offset: 0)
    let sacred = CalendarDef(name: "聖暦", offset: -96)

    @Test func breadcrumbRunsFromTheTopDown() async throws {
        let s = try await TestVault.sample()
        let h = try #require(Manuscript.header(s, path: "場所/鉄鎚亭.md", year: 500, calendar: imperial))
        #expect(h.crumbs.map(\.path) == ["場所/ヴェルダ本土.md", "場所/北ヴェルダ.md", "場所/エルデン邑.md",
                                         "場所/職人街.md", "場所/鉄鎚亭.md"])
        // パンくずの名前もその年の呼び名で出す。
        #expect(h.crumbs.map(\.name).contains("王都エルデン"))
    }

    @Test func titleIsTheNameOfTheYearAndSavedNameAppearsOnlyWhenTheyDiffer() async throws {
        let s = try await TestVault.sample()
        let now = try #require(Manuscript.header(s, path: "場所/エルデン邑.md", year: 600, calendar: imperial))
        #expect(now.title == "エルデン市")
        #expect(now.savedName == "エルデン邑")
        let early = try #require(Manuscript.header(s, path: "場所/エルデン邑.md", year: 200, calendar: imperial))
        #expect(early.title == "エルデン邑")
        #expect(early.savedName == nil)
    }

    @Test func closedPeriodShowsBothEnds() async throws {
        let s = try await TestVault.sample()
        let h = try #require(Manuscript.header(s, path: "場所/鉄鎚亭.md", year: 500, calendar: imperial))
        #expect(h.chips.first(where: { $0.label == "期間" })?.value == "帝国暦 322–588 年")
    }

    @Test func openPeriodEndsWithNow() async throws {
        let s = try await TestVault.sample()
        let h = try #require(Manuscript.header(s, path: "場所/エルデン邑.md", year: 500, calendar: imperial))
        #expect(h.chips.first(where: { $0.label == "期間" })?.value == "帝国暦 96 年–現在")
    }

    @Test func periodFollowsTheChosenCalendar() async throws {
        let s = try await TestVault.sample()
        let h = try #require(Manuscript.header(s, path: "場所/鉄鎚亭.md", year: 500, calendar: sacred))
        #expect(h.chips.first(where: { $0.label == "期間" })?.value == "聖暦 226–492 年")
    }

    @Test func rulerComesFromTheAncestorAndUsesTheNameOfTheYear() async throws {
        let s = try await TestVault.sample()
        // 鉄鎚亭 自身に支配は無い。北ヴェルダ まで遡る。
        let at500 = try #require(Manuscript.header(s, path: "場所/鉄鎚亭.md", year: 500, calendar: imperial))
        #expect(at500.chips.first(where: { $0.label == "支配" })?.value == "北ヴェルダ王国")
        // 600 年の支配は海都同盟で、その年の呼び名は 環海連合。
        let at600 = try #require(Manuscript.header(s, path: "場所/職人街.md", year: 600, calendar: imperial))
        #expect(at600.chips.first(where: { $0.label == "支配" })?.value == "環海連合")
    }

    @Test func lineageAndChildCountAppearOnlyWhenThereIsSomething() async throws {
        let s = try await TestVault.sample()
        let inn = try #require(Manuscript.header(s, path: "場所/鉄鎚亭.md", year: 500, calendar: imperial))
        #expect(inn.chips.map(\.label) == ["期間", "支配"])
        let town = try #require(Manuscript.header(s, path: "場所/エルデン邑.md", year: 600, calendar: imperial))
        #expect(town.chips.first(where: { $0.label == "直下" })?.value == "3 件")
        let polity = try #require(Manuscript.header(s, path: "勢力/北ヴェルダ王国.md", year: 500, calendar: imperial))
        #expect(polity.chips.first(where: { $0.label == "由来" })?.value == "412 分離 ← ヴェルダ帝国")
    }

    @Test func flagsComeOutInAFixedOrder() async throws {
        // 同じ保存名を持つ二つのファイル。どちらもファイル名が保存名と違うので、
        // 重複 と 名前の不一致 の両方が付く。
        let body = "---\n名前: 同じ名前\n種別: 邑\n期間: [1, 現在]\n---\n本文\n"
        let s = try await TestVault.snapshot(["場所/甲.md": body, "場所/乙.md": body])
        let h = try #require(Manuscript.header(s, path: "場所/甲.md", year: 5, calendar: imperial))
        #expect(h.flags == [.nameMismatch, .duplicate])
    }

    @Test func unknownPathHasNoHeader() async throws {
        let s = try await TestVault.sample()
        #expect(Manuscript.header(s, path: "場所/無い.md", year: 500, calendar: imperial) == nil)
    }
}
