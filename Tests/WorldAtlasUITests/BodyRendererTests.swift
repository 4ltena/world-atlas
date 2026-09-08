import Foundation
import Testing
import WorldAtlasCore
@testable import WorldAtlasStore
@testable import WorldAtlasUI

@Suite struct BodyRendererTests {
    func text(_ b: RenderedBlock, _ i: Int = 0) -> String { String(b.lines[i].characters) }
    func links(_ b: RenderedBlock, _ i: Int = 0) -> [URL] { b.lines[i].runs.compactMap(\.link) }

    @Test func blocksKeepTheirShape() async throws {
        let s = try await TestVault.sample()
        let body = """
        ## 城壁

        内壁が積まれた。

        - 一つ目
        - 二つ目
        """
        let bs = BodyRenderer.render(body, snapshot: s, year: 500)
        #expect(bs.map(\.style) == [.heading(2), .paragraph, .bullet])
        #expect(text(bs[0]) == "城壁")
        #expect(bs[2].lines.count == 2)
        #expect(text(bs[2], 1) == "二つ目")
    }

    @Test func resolvedLinkCarriesTheNodeURL() async throws {
        let s = try await TestVault.sample()
        let bs = BodyRenderer.render("鉄は[[職人街]]で打たれる。", snapshot: s, year: 500)
        #expect(text(bs[0]) == "鉄は職人街で打たれる。")
        #expect(links(bs[0]) == [NodeURL.make(path: "場所/職人街.md", arrivedAs: "職人街")])
    }

    @Test func linkTextIsTheNameOfTheYear() async throws {
        let s = try await TestVault.sample()
        #expect(text(BodyRenderer.render("[[エルデン邑]]へ。", snapshot: s, year: 200)[0]) == "エルデン邑へ。")
        #expect(text(BodyRenderer.render("[[エルデン邑]]へ。", snapshot: s, year: 400)[0]) == "王都エルデンへ。")
        #expect(text(BodyRenderer.render("[[エルデン邑]]へ。", snapshot: s, year: 600)[0]) == "エルデン市へ。")
    }

    @Test func writingAnAliasAlsoResolves() async throws {
        // 別名で書いても解決するが、出るのはその年の呼び名である（設計書 14 節）。
        let s = try await TestVault.sample()
        let b = BodyRenderer.render("[[王都エルデン]]へ。", snapshot: s, year: 600)[0]
        #expect(text(b) == "エルデン市へ。")
        #expect(links(b) == [NodeURL.make(path: "場所/エルデン邑.md", arrivedAs: "王都エルデン")])
    }

    @Test func unresolvedLinkStaysAsPlainText() async throws {
        let s = try await TestVault.sample()
        let b = BodyRenderer.render("幻の[[存在しない街]]について。", snapshot: s, year: 500)[0]
        #expect(text(b) == "幻の[[存在しない街]]について。")
        #expect(links(b).isEmpty)
    }

    @Test func emphasisStillWorksAroundALink() async throws {
        let s = try await TestVault.sample()
        let b = BodyRenderer.render("**鉄**は[[職人街]]で。", snapshot: s, year: 500)[0]
        #expect(text(b) == "鉄は職人街で。")
        #expect(links(b).count == 1)
        #expect(b.lines[0].runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
    }

    @Test func severalLinksInOneLine() async throws {
        let s = try await TestVault.sample()
        let b = BodyRenderer.render("[[鉄鎚亭]]と[[三日月書肆]]。", snapshot: s, year: 500)[0]
        #expect(text(b) == "鉄鎚亭と三日月書肆。")
        #expect(links(b) == [NodeURL.make(path: "場所/鉄鎚亭.md", arrivedAs: "鉄鎚亭"),
                             NodeURL.make(path: "場所/三日月書肆.md", arrivedAs: "三日月書肆")])
    }

    @Test func unclosedBracketsAreLeftAlone() async throws {
        let s = try await TestVault.sample()
        #expect(text(BodyRenderer.render("閉じていない [[職人街 の話。", snapshot: s, year: 500)[0])
                == "閉じていない [[職人街 の話。")
    }

    @Test func emptyBodyRendersNothing() async throws {
        let s = try await TestVault.sample()
        #expect(BodyRenderer.render("", snapshot: s, year: 500).isEmpty)
    }
}
