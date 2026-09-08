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

@Suite("絞り込みで当たった名前")
struct TreeMatchedNameTests {

    private func find(_ rows: [TreeNode], _ name: String) -> TreeNode? {
        for r in rows {
            if r.name == name { return r }
            if let x = find(r.children, name) { return x }
        }
        return nil
    }

    @Test("今の年の呼び名と違う名前で当たったら、その名前が入る")
    func differs() async throws {
        let s = try await TestVault.sample()
        let rows = Tree.build(s, kind: .place, year: 500, query: "エルデン市")
        let row = try #require(find(rows, "王都エルデン"))
        #expect(row.matchedName == "エルデン市")
    }

    @Test("今の年の呼び名で当たったら、何も入らない")
    func same() async throws {
        let s = try await TestVault.sample()
        let rows = Tree.build(s, kind: .place, year: 500, query: "王都エルデン")
        let row = try #require(find(rows, "王都エルデン"))
        #expect(row.matchedName == nil)
    }

    @Test("複数当たったら、最も新しい年のものを採る")
    func newest() async throws {
        let s = try await TestVault.sample()
        // 「エルデン」は 保存名 エルデン邑・王都エルデン・エルデン市 の三つに当たる。
        // 500 年の呼び名は 王都エルデン なので、残るのは エルデン邑 と エルデン市。
        let rows = Tree.build(s, kind: .place, year: 500, query: "エルデン")
        let row = try #require(find(rows, "王都エルデン"))
        #expect(row.matchedName == "エルデン市")
    }

    @Test("絞り込んでいないときは何も入らない")
    func noQuery() async throws {
        let s = try await TestVault.sample()
        let rows = Tree.build(s, kind: .place, year: 500)
        #expect(rows.allSatisfy { $0.matchedName == nil })
    }

    @Test("祖先として残っただけの行には何も入らない")
    func ancestor() async throws {
        let s = try await TestVault.sample()
        let rows = Tree.build(s, kind: .place, year: 500, query: "エルデン市")
        let parent = try #require(rows.first { !$0.children.isEmpty })
        #expect(parent.matchedName == nil)
    }

    @Test("保存名がその年の呼び名そのものなら、副の名前は出ない")
    func savedNameIsDisplayName() async throws {
        let s = try await TestVault.sample()
        // 200 年は改称の前。エルデン邑 の呼び名は保存名そのものである。
        let rows = Tree.build(s, kind: .place, year: 200, query: "エルデン邑")
        let row = try #require(find(rows, "エルデン邑"))
        #expect(row.matchedName == nil)
    }

    @Test("当たった行が別の当たった行の祖先でもあるとき、副の名前が消えない")
    func hitThatIsAlsoAnAncestor() async throws {
        let s = try await TestVault.snapshot([
            "場所/北都.md": """
            ---
            名前: 北都
            種別: 都市
            期間: [1, 現在]
            別名:
              - [200, 北府]
            ---
            """,
            "場所/北都街.md": """
            ---
            名前: 北都街
            種別: 区
            期間: [1, 現在]
            親: 北都
            ---
            """,
        ])
        // 300 年。「北」は両方に当たる。北都 の呼び名は 北府 なので副に 北都 が付き、
        // 北都街 は呼び名そのものに当たったので副は付かない。
        let rows = Tree.build(s, kind: .place, year: 300, query: "北")
        let parent = try #require(find(rows, "北府"))
        #expect(parent.matchedName == "北都")
        let child = try #require(find(parent.children, "北都街"))
        #expect(child.matchedName == nil)
    }
}
