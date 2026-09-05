import Testing
import WorldAtlasCore
@testable import WorldAtlasStore
@testable import WorldAtlasUI

@Suite struct TreeTests {
    @Test func placeTreeFollowsTheSnapshotOrder() async throws {
        let s = try await TestVault.sample()
        let roots = Tree.build(s, kind: .place, year: 500)
        #expect(Set(roots.map(\.path)) == ["場所/ヴェルダ本土.md", "場所/灰嶺.md", "場所/環海諸島.md"])
        let district = try #require(find(roots, "場所/職人街.md"))
        #expect(district.children.map(\.path) == ["場所/鉄鎚亭.md", "場所/ヴォルフ鍛冶場.md", "場所/三日月書肆.md", "場所/新鉄鎚亭.md"])
        #expect(district.category == "区")
    }

    @Test func rowsUseTheNameOfTheYear() async throws {
        let s = try await TestVault.sample()
        func eldenName(at y: Int) throws -> String {
            try #require(find(Tree.build(s, kind: .place, year: y), "場所/エルデン邑.md")).name
        }
        #expect(try eldenName(at: 200) == "エルデン邑")
        #expect(try eldenName(at: 400) == "王都エルデン")
        #expect(try eldenName(at: 600) == "エルデン市")
    }

    @Test func queryKeepsHitsAndTheirAncestors() async throws {
        let s = try await TestVault.sample()
        let roots = Tree.build(s, kind: .place, year: 500, query: "鉄")
        #expect(roots.map(\.path) == ["場所/ヴェルダ本土.md"])
        #expect(paths(roots) == ["場所/ヴェルダ本土.md", "場所/北ヴェルダ.md", "場所/エルデン邑.md",
                                 "場所/職人街.md", "場所/鉄鎚亭.md", "場所/新鉄鎚亭.md"])
    }

    @Test func queryMatchesAliasesEvenWhenNotShownThatYear() async throws {
        // 200 年の呼び名は「エルデン邑」だが、別名「王都エルデン」でも当たる。
        let s = try await TestVault.sample()
        let roots = Tree.build(s, kind: .place, year: 200, query: "王都")
        #expect(paths(roots).contains("場所/エルデン邑.md"))
        #expect(find(roots, "場所/エルデン邑.md")?.name == "エルデン邑")
    }

    @Test func queryWithNoHitLeavesAnEmptyTree() async throws {
        let s = try await TestVault.sample()
        #expect(Tree.build(s, kind: .place, year: 500, query: "存在しない名前").isEmpty)
    }

    @Test func blankQueryIsNotAFilter() async throws {
        let s = try await TestVault.sample()
        #expect(paths(Tree.build(s, kind: .place, year: 500, query: "   "))
                == paths(Tree.build(s, kind: .place, year: 500)))
    }

    @Test func branchesAreTheRowsThatHaveChildren() async throws {
        let s = try await TestVault.sample()
        let b = Tree.branches(Tree.build(s, kind: .place, year: 500, query: "鉄"))
        #expect(b == ["場所/ヴェルダ本土.md", "場所/北ヴェルダ.md", "場所/エルデン邑.md", "場所/職人街.md"])
    }

    @Test func brokenNodesStillAppearWithTheirFlag() async throws {
        let s = try await TestVault.snapshot([
            "場所/壊れ.md": "---\n名前: 壊れ\n期間: これは年ではない\n---\n本文\n",
        ])
        let roots = Tree.build(s, kind: .place, year: 500)
        #expect(roots.count == 1)
        #expect(roots[0].flags.contains(.broken))
        #expect(roots[0].name == "壊れ")
    }

    @Test func eventsHaveNoParentsSoTheyAreAllRoots() async throws {
        let s = try await TestVault.sample()
        let roots = Tree.build(s, kind: .event, year: 500)
        #expect(roots.allSatisfy { $0.children.isEmpty })
        #expect(roots.count == (s.roots[.event] ?? []).count)
    }

    // 木を前順に平らにする。
    private func paths(_ ns: [TreeNode]) -> [String] {
        ns.flatMap { [$0.path] + paths($0.children) }
    }
    private func find(_ ns: [TreeNode], _ path: String) -> TreeNode? {
        for n in ns {
            if n.path == path { return n }
            if let f = find(n.children, path) { return f }
        }
        return nil
    }
}
