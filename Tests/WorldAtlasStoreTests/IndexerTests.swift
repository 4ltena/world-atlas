import Foundation
import Testing
import WorldAtlasCore
@testable import WorldAtlasStore

@Suite struct IndexerTests {
    @Test func rebuildIndexesTheSampleVault() async throws {
        let vault = try SampleVault.copy()
        let indexer = try Indexer(vault: vault)
        let s = try await indexer.rebuild()
        #expect(s.world.name == "灰海")
        #expect(s.nodes.count == 66)
        #expect(s.nodes.values.allSatisfy { $0.flags.isEmpty })
        #expect(Set(s.roots[.place] ?? []) == ["場所/ヴェルダ本土.md", "場所/灰嶺.md", "場所/環海諸島.md"])
        // 木の順は開始年、同年は名前。年表の行と揃える。
        #expect(s.children["場所/職人街.md"] == ["場所/鉄鎚亭.md", "場所/ヴォルフ鍛冶場.md", "場所/三日月書肆.md", "場所/新鉄鎚亭.md"])
        #expect(s.nodes["場所/職人街.md"]?.parentPath == "場所/エルデン邑.md")
        #expect(s.extent == Extent(lo: 1, hi: 712))
        #expect(s.ignoredDirectories == 0)
    }

    @Test func refsResolveAliasesAndReverse() async throws {
        let indexer = try Indexer(vault: try SampleVault.copy())
        let s = try await indexer.rebuild()
        #expect(s.refs["場所/職人街.md"] == ["出来事/職人街の大火.md", "場所/鉄鎚亭.md", "場所/三日月書肆.md", "法律/鉄の掟.md"])
        #expect(s.backrefs["場所/鉄鎚亭.md"]?.contains("場所/職人街.md") == true)
        #expect(s.backrefs["場所/鉄鎚亭.md"]?.contains("場所/新鉄鎚亭.md") == true)
        #expect(s.unresolved.isEmpty)
    }

    @Test func aliasInBodyResolvesToSavedName() async throws {
        let vault = try SampleVault.copy()
        let file = vault.appendingPathComponent("場所/川向こう.md")
        try (String(contentsOf: file, encoding: .utf8) + "\n[[王都エルデン]]の外。\n").write(to: file, atomically: true, encoding: .utf8)
        let s = try await Indexer(vault: vault).rebuild()
        #expect(s.refs["場所/川向こう.md"] == ["場所/エルデン邑.md"])
    }

    @Test func brokenFileIsFlaggedNotFatal() async throws {
        let vault = try SampleVault.copy()
        try "---\n種別: 区\n---\n".write(to: vault.appendingPathComponent("場所/壊れた.md"), atomically: true, encoding: .utf8)
        let s = try await Indexer(vault: vault).rebuild()
        #expect(s.nodes["場所/壊れた.md"]?.flags == [.broken])
        #expect(s.nodes["場所/壊れた.md"]?.name == "壊れた")
        #expect(s.nodes.count == 67)
    }

    @Test func duplicateNamesKeepBothFilesAndFlagBoth() async throws {
        let vault = try SampleVault.copy()
        try "---\n名前: 石橋\n種別: 橋\n期間: [1, 現在]\n---\n".write(to: vault.appendingPathComponent("アイテム/石橋.md"), atomically: true, encoding: .utf8)
        let s = try await Indexer(vault: vault).rebuild()
        #expect(s.nodes["場所/石橋.md"]?.flags == [.duplicate])
        #expect(s.nodes["アイテム/石橋.md"]?.flags == [.duplicate])
        #expect(s.names["石橋"]?.count == 2)
        #expect(s.path(ofName: "石橋") == nil)
        // 曖昧な名前へのリンクは解決されず、未解決に数える。
        #expect(s.refs["勢力/ヴェルダ王国.md"]?.contains("場所/石橋.md") == false)
        #expect(s.unresolved["勢力/ヴェルダ王国.md"] == ["石橋"])
    }

    @Test func aliasCollidingWithASavedNameIsNotADuplicate() async throws {
        let vault = try SampleVault.copy()
        // 別名が既存の保存名 石橋 と同じ節点を足す。保存名は衝突していない。
        try "---\n名前: 仮橋\n種別: 橋\n期間: [1, 現在]\n別名:\n  - [100, 石橋]\n---\n"
            .write(to: vault.appendingPathComponent("アイテム/仮橋.md"), atomically: true, encoding: .utf8)
        let s = try await Indexer(vault: vault).rebuild()
        #expect(s.nodes["場所/石橋.md"]?.flags.isEmpty == true)
        #expect(s.nodes["アイテム/仮橋.md"]?.flags.isEmpty == true)
        // 本文のリンクは曖昧になり解決しない。保存名で引けば一意である。
        #expect(s.path(ofName: "石橋") == nil)
        #expect(s.path(ofSavedName: "石橋") == "場所/石橋.md")
        #expect(s.unresolved["勢力/ヴェルダ王国.md"] == ["石橋"])
    }

    @Test func parentIsResolvedBySavedNameOnly() async throws {
        let vault = try SampleVault.copy()
        // 別名 職人街 を持つ別の区を足す。親が 職人街 の子は、保存名の 職人街 に付いたままである。
        try "---\n名前: 仮の区\n種別: 区\n期間: [1, 現在]\n親: エルデン邑\n別名:\n  - [100, 職人街]\n---\n"
            .write(to: vault.appendingPathComponent("場所/仮の区.md"), atomically: true, encoding: .utf8)
        let s = try await Indexer(vault: vault).rebuild()
        #expect(s.nodes["場所/鉄鎚亭.md"]?.parentPath == "場所/職人街.md")
    }

    @Test func mismatchAndDuplicateCoexist() async throws {
        let vault = try SampleVault.copy()
        // ファイル名 橋詰、保存名 旧橋詰（不一致）。もう一つ、保存名 旧橋詰 のファイルを足す（重複）。
        try FileManager.default.moveItem(at: vault.appendingPathComponent("場所/旧橋詰.md"), to: vault.appendingPathComponent("場所/橋詰.md"))
        try "---\n名前: 旧橋詰\n種別: 区\n期間: [1, 現在]\n---\n".write(to: vault.appendingPathComponent("アイテム/旧橋詰.md"), atomically: true, encoding: .utf8)
        let s = try await Indexer(vault: vault).rebuild()
        #expect(s.nodes["場所/橋詰.md"]?.flags == [.nameMismatch, .duplicate])
        #expect(s.nodes["アイテム/旧橋詰.md"]?.flags == [.duplicate])
        // 重複を解くと不一致だけが残る。
        try FileManager.default.removeItem(at: vault.appendingPathComponent("アイテム/旧橋詰.md"))
        let indexer = try Indexer(vault: vault)
        let s2 = try await indexer.rebuild()
        #expect(s2.nodes["場所/橋詰.md"]?.flags == [.nameMismatch])
    }

    @Test func rulersInheritFromAncestors() async throws {
        let s = try await Indexer(vault: try SampleVault.copy()).rebuild()
        // 職人街 は支配を書いていない。エルデン邑 も無い。北ヴェルダ から継ぐ。
        #expect(s.rulers(of: "場所/職人街.md", at: 500).map(\.name) == ["北ヴェルダ王国"])
        // 区間は終了を含まない。412 は 北ヴェルダ王国。
        #expect(s.rulers(of: "場所/北ヴェルダ.md", at: 412).map(\.name) == ["北ヴェルダ王国"])
        #expect(s.rulers(of: "場所/北ヴェルダ.md", at: 411).map(\.name) == ["ヴェルダ王国"])
        // 現在 で終わる支配は開区間。
        #expect(s.rulers(of: "場所/ヴォルフ鍛冶場.md", at: 700).map(\.name) == ["海都同盟"])
        // どこにも無ければ空。
        #expect(s.rulers(of: "場所/灰嶺.md", at: 500).isEmpty)
    }

    @Test func reindexOneFileUpdatesOnlyItsRows() async throws {
        let vault = try SampleVault.copy()
        let indexer = try Indexer(vault: vault)
        _ = try await indexer.rebuild()
        let file = vault.appendingPathComponent("場所/川向こう.md")
        try "---\n名前: 川向こう\n種別: 区\n期間: [520, 現在]\n親: エルデン邑\n---\n[[石橋]]を見る。\n".write(to: file, atomically: true, encoding: .utf8)
        let s = try await indexer.reindex([file])
        #expect(s.refs["場所/川向こう.md"] == ["場所/石橋.md"])
        #expect(s.backrefs["場所/石橋.md"]?.contains("場所/川向こう.md") == true)
        #expect(s.nodes.count == 66)
    }

    @Test func reindexDeletedFileRemovesTheNode() async throws {
        let vault = try SampleVault.copy()
        let indexer = try Indexer(vault: vault)
        _ = try await indexer.rebuild()
        let file = vault.appendingPathComponent("場所/川向こう.md")
        try FileManager.default.removeItem(at: file)
        let s = try await indexer.reindex([file])
        #expect(s.nodes["場所/川向こう.md"] == nil)
        #expect(s.children["場所/エルデン邑.md"]?.contains("場所/川向こう.md") == false)
    }

    @Test func reindexWorldFileRefreshesCalendars() async throws {
        let vault = try SampleVault.copy()
        let indexer = try Indexer(vault: vault)
        _ = try await indexer.rebuild()
        let file = vault.appendingPathComponent("世界.yaml")
        try "名前: 灰海\n基準暦: 帝国暦\n暦:\n  - [帝国暦, 0]\n  - [新暦, 300]\n現在: 500\n".write(to: file, atomically: true, encoding: .utf8)
        let s = try await indexer.reindex([file])
        #expect(s.world.calendars.map(\.name) == ["帝国暦", "新暦"])
    }

    @Test func bodyIsReadFromDisk() async throws {
        let indexer = try Indexer(vault: try SampleVault.copy())
        _ = try await indexer.rebuild()
        let body = try await indexer.body(of: "場所/鉄鎚亭.md")
        #expect(body.hasPrefix("[[職人街]]ができた四年後"))
    }

    @Test func unknownDirectoriesAreCounted() async throws {
        let vault = try SampleVault.copy()
        try FileManager.default.createDirectory(at: vault.appendingPathComponent("下書き"), withIntermediateDirectories: true)
        let s = try await Indexer(vault: vault).rebuild()
        #expect(s.ignoredDirectories == 1)
    }
}
