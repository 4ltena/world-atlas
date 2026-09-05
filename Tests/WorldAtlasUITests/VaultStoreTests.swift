import Foundation
import Testing
import WorldAtlasCore
@testable import WorldAtlasStore
@testable import WorldAtlasUI

@Suite struct VaultStoreTests {
    @Test @MainActor func loadsTheSampleVault() async throws {
        let store = VaultStore(vault: try TestVault.copiedSample())
        await store.load()
        defer { Task { await store.stop() } }
        #expect(store.loadError == nil)
        #expect(store.snapshot.nodes.count == 66)
        // 年と暦は 世界.yaml の 現在 と 基準暦 から始まる。
        #expect(store.year == 500)
        #expect(store.calendar == CalendarDef(name: "帝国暦", offset: 0))
    }

    @Test @MainActor func withNothingSelectedTheTextIsTheWorldNote() async throws {
        let store = VaultStore(vault: try TestVault.copiedSample())
        await store.load()
        #expect(store.selected == nil)
        #expect(store.text.contains("内海をはさんで"))
        #expect(store.blocks.isEmpty == false)
    }

    @Test @MainActor func aVaultWithoutAWorldNoteHasEmptyText() async throws {
        let v = try TestVault.copiedSample()
        try FileManager.default.removeItem(at: v.appendingPathComponent("世界.md"))
        let store = VaultStore(vault: v)
        await store.load()
        #expect(store.selected == nil)
        #expect(store.text.isEmpty)
    }

    @Test @MainActor func selectingReadsTheBodyAndRemembersIt() async throws {
        let v = try TestVault.copiedSample()
        let store = VaultStore(vault: v)
        await store.load()
        store.select("場所/職人街.md")
        // 本文の読み込みは非同期なので、値が入るまで待つ。
        try await until { store.text.contains("外壁の内側") }
        #expect(store.header?.title == "職人街")
        #expect(VaultState.read(vault: v).openNode == "場所/職人街.md")
        // 表示は front matter を落としたもの、原文は全文。
        #expect(!store.text.contains("名前: 職人街"))
        #expect(store.raw.hasPrefix("---"))
        #expect(store.raw.contains("名前: 職人街"))
    }

    @Test @MainActor func theRememberedNodeIsOpenedNextTime() async throws {
        let v = try TestVault.copiedSample()
        VaultState.write(VaultState(openNode: "場所/鉄鎚亭.md"), vault: v)
        let store = VaultStore(vault: v)
        await store.load()
        #expect(store.selected == "場所/鉄鎚亭.md")
        #expect(store.kind == .place)
    }

    @Test @MainActor func aRememberedNodeThatIsGoneFallsBackToNothing() async throws {
        let v = try TestVault.copiedSample()
        VaultState.write(VaultState(openNode: "場所/もう無い.md"), vault: v)
        let store = VaultStore(vault: v)
        await store.load()
        #expect(store.selected == nil)
        #expect(store.loadError == nil)
    }

    @Test @MainActor func selectingAcrossKindsSwitchesTheRailAndOpensTheAncestors() async throws {
        let store = VaultStore(vault: try TestVault.copiedSample())
        await store.load()
        store.select("場所/鉄鎚亭.md")
        #expect(store.kind == .place)
        // 木の中で見えるように、祖先を開いておく。
        #expect(store.expanded.isSuperset(of: ["場所/ヴェルダ本土.md", "場所/北ヴェルダ.md",
                                               "場所/エルデン邑.md", "場所/職人街.md"]))
        store.select("法律/鉄の掟.md")
        #expect(store.kind == .law)
    }

    @Test @MainActor func goingToTheParent() async throws {
        let store = VaultStore(vault: try TestVault.copiedSample())
        await store.load()
        store.select("場所/鉄鎚亭.md")
        store.goToParent()
        #expect(store.selected == "場所/職人街.md")
        // 型の直下では何も起きない。
        store.select("場所/ヴェルダ本土.md")
        store.goToParent()
        #expect(store.selected == "場所/ヴェルダ本土.md")
    }

    @Test @MainActor func searchingOpensTheRowsThatLeadToTheHits() async throws {
        let store = VaultStore(vault: try TestVault.copiedSample())
        await store.load()
        store.query = "鉄"
        #expect(store.rows.map(\.path) == ["場所/ヴェルダ本土.md"])
        #expect(store.expanded.isSuperset(of: ["場所/ヴェルダ本土.md", "場所/職人街.md"]))
    }

    @Test @MainActor func aBrokenNodeCanOnlyBeSeenAsItsSource() async throws {
        // 設計書 4.4。front matter が読めない節点は、直す手がかりが原文しか無い。
        let v = try TestVault.copiedSample()
        try "---\n名前: 壊れ\n期間: これは年ではない\n---\n本文\n"
            .write(to: v.appendingPathComponent("場所/壊れ.md"), atomically: true, encoding: .utf8)
        let store = VaultStore(vault: v)
        await store.load()
        store.select("場所/壊れ.md")
        #expect(store.isBroken)
        #expect(store.showsRawEffectively)
        // 「表示」を選んでも原文のままである。
        store.showsRaw = false
        #expect(store.showsRawEffectively)
        // 壊れていない節点では、選んだ区分けがそのまま効く。
        store.select("場所/職人街.md")
        #expect(!store.isBroken)
        #expect(!store.showsRawEffectively)
    }

    @Test @MainActor func aBrokenWorldFileIsReported() async throws {
        let v = try TestVault.copiedSample()
        try "これは YAML ではない: [".write(to: v.appendingPathComponent("世界.yaml"), atomically: true, encoding: .utf8)
        let store = VaultStore(vault: v)
        await store.load()
        #expect(store.loadError != nil)
        #expect(store.snapshot.nodes.isEmpty)
    }

    @Test @MainActor func changesOnDiskReachTheStore() async throws {
        let v = try TestVault.copiedSample()
        let store = VaultStore(vault: v)
        await store.load()
        defer { Task { await store.stop() } }
        let before = store.snapshot.nodes.count
        try """
        ---
        名前: 新しい邑
        種別: 邑
        期間: [700, 現在]
        ---
        あとから足した。

        """.write(to: v.appendingPathComponent("場所/新しい邑.md"), atomically: true, encoding: .utf8)
        try await until { store.snapshot.nodes.count == before + 1 }
        #expect(store.snapshot.nodes["場所/新しい邑.md"]?.name == "新しい邑")
    }

    @Test @MainActor func aSupersededReadNeverShowsItsBody() async throws {
        // 選び直したその場で古い読み込みを無効にしないと、先の読み込みが await から戻った
        // ときに前の節点の本文を書けてしまう。落ち着いた先の値は正しくなるので、途中で
        // 通り過ぎる値を見て確かめる。隙に入れるかどうかは main の混み具合で決まるので、
        // 入れなかった回は数えずに何度か試す。
        let store = VaultStore(vault: try TestVault.copiedSample())
        await store.load()
        let district = "外壁の内側"    // 場所/職人街.md の本文
        let inn = "四年後に建った宿"   // 場所/鉄鎚亭.md の本文
        for _ in 0..<8 {
            store.select(nil)
            try await until { store.text.contains("内海をはさんで") }
            store.select("場所/職人街.md")
            // 職人街 の読み込みを最初の待ちまで進めてから、その続きと同じ列に並べて選び直す。
            await Task.yield()
            let switched = Task { @MainActor () -> String in
                let before = store.text
                store.select("場所/鉄鎚亭.md")
                return before
            }
            // 譲るたびに見る。until の 50 ミリ秒の待ちでは、一瞬の食い違いを通り越す。
            var seen: [String] = []
            let deadline = ContinuousClock.now + .seconds(5)
            while !store.text.contains(inn) {
                if seen.last != store.text { seen.append(store.text) }
                guard ContinuousClock.now < deadline else {
                    Issue.record("鉄鎚亭 の本文が来なかった")
                    return
                }
                await Task.yield()
            }
            // 選び直した時点で既に 職人街 の本文が出ていたなら、隙に入れていない回である。
            let before = await switched.value
            if before.contains(district) { continue }
            #expect(!seen.contains { $0.contains(district) })
        }
    }

    /// 条件が成り立つまで、間を置いて確かめる。監視は非同期なので待ちが要る。
    @MainActor
    private func until(_ limit: Duration = .seconds(5), _ cond: () -> Bool) async throws {
        let deadline = ContinuousClock.now + limit
        while ContinuousClock.now < deadline {
            if cond() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("待ち時間 \(limit) の中で条件が成り立たなかった")
    }
}
