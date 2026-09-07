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

    @Test @MainActor func yearIsClampedToTheWorldPlusTen() async throws {
        let store = VaultStore(vault: try TestVault.copiedSample())
        await store.load()
        store.setYear(-500)
        #expect(store.year == store.snapshot.extent.lo)
        store.setYear(99_999)
        #expect(store.year == store.snapshot.extent.hi + 10)
    }

    @Test @MainActor func theYearIsWrittenBackToTheWorldFile() async throws {
        let v = try TestVault.copiedSample()
        let store = VaultStore(vault: v)
        await store.load()
        store.writeDelay = .milliseconds(20)   // 試験のために縮める
        store.setYear(404)
        try await until { (try? String(contentsOf: v.appendingPathComponent("世界.yaml"), encoding: .utf8))?
                            .contains("現在: 404") == true }
    }

    @Test @MainActor func closingTheWindowFlushesThePendingWrite() async throws {
        // 動かして 1 秒以内に閉じても消えない(設計書 4.2)。待たずに stop() を呼ぶ。
        let v = try TestVault.copiedSample()
        let store = VaultStore(vault: v)
        await store.load()
        store.setYear(404)                      // writeDelay は既定の 1 秒のまま
        await store.stop()
        let text = try String(contentsOf: v.appendingPathComponent("世界.yaml"), encoding: .utf8)
        #expect(text.contains("現在: 404"))
    }

    @Test @MainActor func rapidYearChangesWriteOnlyTheLastOne() async throws {
        let v = try TestVault.copiedSample()
        let store = VaultStore(vault: v)
        await store.load()
        store.writeDelay = .milliseconds(40)
        for y in [310, 320, 330, 340] { store.setYear(y) }
        try await until { (try? String(contentsOf: v.appendingPathComponent("世界.yaml"), encoding: .utf8))?
                            .contains("現在: 340") == true }
        let text = try String(contentsOf: v.appendingPathComponent("世界.yaml"), encoding: .utf8)
        #expect(!text.contains("現在: 310"))
    }

    @Test @MainActor func theScaleIsRememberedAsAYearRange() async throws {
        let v = try TestVault.copiedSample()
        let store = VaultStore(vault: v)
        await store.load()
        store.writeDelay = .milliseconds(20)
        store.ensureScale(width: 800)
        store.fitScale(width: 800)
        try await until { VaultState.read(vault: v).visibleFrom != nil }
        let saved = VaultState.read(vault: v)
        #expect(saved.visibleTo! > saved.visibleFrom!)
    }

    @Test @MainActor func aRememberedScaleIsRestoredIntoTheCurrentWidth() async throws {
        let v = try TestVault.copiedSample()
        VaultState.write(VaultState(openNode: nil, visibleFrom: 300, visibleTo: 500), vault: v)
        let store = VaultStore(vault: v)
        await store.load()
        store.ensureScale(width: 400)
        let t = try #require(store.scale)
        #expect(abs(t.origin - 300) < 0.5)
        #expect(abs(t.years - 200) < 0.5)
        #expect(t.width == 400)   // 幅は今の窓のもの
    }

    @Test @MainActor func aNarrowRememberedScaleIsNotWidenedToFortyYears() async throws {
        // 12 年まで寄せて閉じたら、12 年で開く。fitting を通すと 40 年へ広がってしまう。
        let v = try TestVault.copiedSample()
        VaultState.write(VaultState(openNode: nil, visibleFrom: 300, visibleTo: 312), vault: v)
        let store = VaultStore(vault: v)
        await store.load()
        store.ensureScale(width: 800)
        let t = try #require(store.scale)
        #expect(abs(t.origin - 300) < 0.5)
        #expect(abs(t.years - 12) < 0.5)
    }

    @Test @MainActor func theScaleIsNotDecidedBeforeTheIndexIsBuilt() async throws {
        // 窓は load を待たずに一度組まれるので、ensureScale は空の Snapshot で先に呼ばれる。
        // そこで決めると、幅が変わらないかぎり作り直す契機が無く、狂ったまま残る。
        let store = VaultStore(vault: try TestVault.copiedSample())
        store.ensureScale(width: 800)
        #expect(store.scale == nil)
        await store.load()
        store.ensureScale(width: 800)
        let t = try #require(store.scale)
        #expect(abs(t.origin - Double(store.snapshot.extent.lo)) < 0.5)
    }

    @Test @MainActor func theSubtitleNamesTheRootAndTheVisibleRange() async throws {
        // 設計書 8.1 の `根 職人街｜264–760（世界の 65%）`。
        let store = VaultStore(vault: try TestVault.copiedSample())
        await store.load()
        // 尺が決まる前は根だけ。何も選んでいなければ根は型の名である。
        #expect(store.timelineSubtitle == "根 場所")
        store.select("場所/職人街.md")
        store.ensureScale(width: 800)
        store.showWholeWorld(width: 800)
        #expect(store.timelineSubtitle.hasPrefix("根 職人街｜"))
        #expect(store.timelineSubtitle.hasSuffix("（世界の 100%）"))
        // 暦を替えると副題の年も替わる。
        store.setCalendar("海都暦")
        let e = store.snapshot.extent
        #expect(store.timelineSubtitle.contains("\(e.lo + 178)–"))
    }

    @Test @MainActor func withoutARememberedScaleTheWholeWorldIsShown() async throws {
        let store = VaultStore(vault: try TestVault.copiedSample())
        await store.load()
        store.ensureScale(width: 800)
        let t = try #require(store.scale)
        #expect(abs(t.origin - Double(store.snapshot.extent.lo)) < 0.5)
    }

    @Test @MainActor func timelineRowsFollowTheSelection() async throws {
        let store = VaultStore(vault: try TestVault.copiedSample())
        await store.load()
        #expect(store.timelineRows.allSatisfy { !$0.isRoot })    // 何も選んでいない
        store.select("場所/職人街.md")
        #expect(store.timelineRows.first?.path == "場所/職人街.md")
        #expect(store.timelineRows.first?.isRoot == true)
    }

    @Test @MainActor func draggingTheYearMovesTheTreeAtOnce() async throws {
        // 設計書 8.6（2026-09-06 に改めた）。掴んでいる最中から呼び名が追随する。
        // 木は入れ子なので、探す前に平らにする。
        func flatten(_ ns: [TreeNode]) -> [TreeNode] { ns.flatMap { [$0] + flatten($0.children) } }
        let store = VaultStore(vault: try TestVault.copiedSample())
        await store.load()
        func eldenName() -> String? {
            flatten(store.rows).first { $0.path == "場所/エルデン邑.md" }?.name
        }
        #expect(store.year == 500)                 // 見本の 世界.yaml の 現在
        #expect(eldenName() == "王都エルデン")      // 318 年からの呼び名
        store.draggingYear = 600
        #expect(store.displayedYear == 600)
        #expect(eldenName() == "エルデン市")        // **掴んでいる最中から変わる**
        store.setYear(600)
        store.draggingYear = nil
        #expect(eldenName() == "エルデン市")        // 離しても同じ
        // 掴みを捨てた（離さずに取り消した）ら、確定した年の呼び名へ戻る。
        store.draggingYear = 200
        #expect(eldenName() == "エルデン邑")
        store.draggingYear = nil
        #expect(eldenName() == "エルデン市")
    }

    @Test @MainActor func collapsingRemembersTheHeight() async throws {
        // 高さはアプリ全体の値なので、試験の前後で元へ戻す。
        let d = UserDefaults.standard
        let before = d.object(forKey: VaultStore.timelineHeightKey)
        defer {
            if let before { d.set(before, forKey: VaultStore.timelineHeightKey) }
            else { d.removeObject(forKey: VaultStore.timelineHeightKey) }
        }
        let store = VaultStore(vault: try TestVault.copiedSample())
        await store.load()
        store.setTimelineHeight(260)
        store.timelineCollapsed = true
        store.timelineCollapsed = false
        #expect(store.timelineHeight == 260)
        // 別の窓を開いても同じ高さで始まる（設計書 11 節の @AppStorage の欄）。
        let other = VaultStore(vault: try TestVault.copiedSample())
        #expect(other.timelineHeight == 260)
    }

    @Test @MainActor func theCalendarIsRememberedPerVault() async throws {
        let v = try TestVault.copiedSample()
        let store = VaultStore(vault: v)
        await store.load()
        #expect(store.calendarName == store.snapshot.world.baseCalendar)
        store.setCalendar("海都暦")
        #expect(VaultState.read(vault: v).calendar == "海都暦")
        let again = VaultStore(vault: v)
        await again.load()
        #expect(again.calendarName == "海都暦")
    }

    @Test @MainActor func aRememberedCalendarThatNoLongerExistsFallsBack() async throws {
        // 世界.yaml から暦が消されていることがある。黙って基準暦へ戻す（設計書 11 節）。
        let v = try TestVault.copiedSample()
        VaultState.write(VaultState(openNode: nil, calendar: "存在しない暦"), vault: v)
        let store = VaultStore(vault: v)
        await store.load()
        #expect(store.calendarName == store.snapshot.world.baseCalendar)
    }

    @Test @MainActor func selectingANodeKeepsTheRememberedScale() async throws {
        // 既存の select は VaultState を丸ごと書き直していた。尺を消してはいけない。
        let v = try TestVault.copiedSample()
        VaultState.write(VaultState(openNode: nil, visibleFrom: 300, visibleTo: 500), vault: v)
        let store = VaultStore(vault: v)
        await store.load()
        store.select("場所/職人街.md")
        let saved = VaultState.read(vault: v)
        #expect(saved.openNode == "場所/職人街.md")
        #expect(saved.visibleFrom == 300)
        #expect(saved.visibleTo == 500)
    }

    @Test @MainActor func savingWritesTheFileAndReindexes() async throws {
        let v = try TestVault.copiedSample()
        let store = VaultStore(vault: v)
        await store.load()
        store.select("場所/鉄鎚亭.md")
        try await until { store.raw.contains("鉄鎚亭") }
        store.editedText = store.editedText.replacingOccurrences(of: "種別: 宿", with: "種別: 旅籠")
        #expect(store.isDirty)
        #expect(store.save())
        // ファイルに書かれている。
        let text = try String(contentsOf: v.appendingPathComponent("場所/鉄鎚亭.md"), encoding: .utf8)
        #expect(text.contains("種別: 旅籠"))
        // 索引にも入っている。
        try await until { store.snapshot.nodes["場所/鉄鎚亭.md"]?.category == "旅籠" }
        #expect(!store.isDirty)
        #expect(store.saveError == nil)
    }

    @Test @MainActor func abrokenFrontMatterIsNotWritten() async throws {
        let v = try TestVault.copiedSample()
        let store = VaultStore(vault: v)
        await store.load()
        store.select("場所/鉄鎚亭.md")
        try await until { store.raw.contains("鉄鎚亭") }
        let before = try String(contentsOf: v.appendingPathComponent("場所/鉄鎚亭.md"), encoding: .utf8)
        store.editedText = "front matter を消してしまった。"
        #expect(!store.save())
        // **書いていない。**
        let after = try String(contentsOf: v.appendingPathComponent("場所/鉄鎚亭.md"), encoding: .utf8)
        #expect(after == before)
        // 行番号つきの理由が出ている。
        let reason = try #require(store.saveError)
        #expect(reason.hasPrefix("1 行目"))
        #expect(store.isDirty)          // 編集は残っている
    }

    @Test @MainActor func fixingTheErrorAndSavingAgainClearsTheReason() async throws {
        let v = try TestVault.copiedSample()
        let store = VaultStore(vault: v)
        await store.load()
        store.select("場所/鉄鎚亭.md")
        try await until { store.raw.contains("鉄鎚亭") }
        let sound = store.editedText
        store.editedText = "壊した。"
        #expect(!store.save())
        #expect(store.saveError != nil)
        store.editedText = sound + "\n直した。"
        #expect(store.save())
        #expect(store.saveError == nil)
    }

    @Test @MainActor func savingWithNothingChangedDoesNothingAndSucceeds() async throws {
        let store = VaultStore(vault: try TestVault.copiedSample())
        await store.load()
        store.select("場所/鉄鎚亭.md")
        try await until { store.raw.contains("鉄鎚亭") }
        #expect(!store.isDirty)
        #expect(store.save())          // 何も書かずに通る
        #expect(store.saveError == nil)
    }

    @Test @MainActor func theWorldFileCanBeEditedAndSaved() async throws {
        // 何も選んでいないときは 世界.md を編集している。front matter は無い。
        let v = try TestVault.copiedSample()
        let store = VaultStore(vault: v)
        await store.load()
        store.select(nil)
        store.editedText = "灰海は塩と鉄の海である。"
        #expect(store.save())
        let text = try String(contentsOf: v.appendingPathComponent("世界.md"), encoding: .utf8)
        #expect(text == "灰海は塩と鉄の海である。")
    }

    @Test @MainActor func anOutsideChangeIsTakenWhenNotEditing() async throws {
        let v = try TestVault.copiedSample()
        let store = VaultStore(vault: v)
        await store.load()
        await store.stopWatchingForTest()   // 索引し直すのはこの試験だけ
        store.select("場所/鉄鎚亭.md")
        try await until { store.raw.contains("鉄鎚亭") }
        // 外のエディタが書き換えた体で、直に書いて索引し直す。
        let url = v.appendingPathComponent("場所/鉄鎚亭.md")
        let outside = try String(contentsOf: url, encoding: .utf8) + "\n外で足した。"
        try outside.write(to: url, atomically: true, encoding: .utf8)
        await store.reindexForTest([url])
        #expect(store.raw.hasSuffix("外で足した。"))
        #expect(!store.changedOutside)      // 編集していないので知らせることは無い
        #expect(!store.isDirty)
    }

    @Test @MainActor func anOutsideChangeIsHeldBackWhileEditing() async throws {
        let v = try TestVault.copiedSample()
        let store = VaultStore(vault: v)
        await store.load()
        await store.stopWatchingForTest()   // 索引し直すのはこの試験だけ
        store.select("場所/鉄鎚亭.md")
        try await until { store.raw.contains("鉄鎚亭") }
        store.editedText = store.editedText + "\nこちらの編集。"
        let url = v.appendingPathComponent("場所/鉄鎚亭.md")
        let outside = try String(contentsOf: url, encoding: .utf8) + "\n外で足した。"
        try outside.write(to: url, atomically: true, encoding: .utf8)
        await store.reindexForTest([url])
        // **編集中の文字列を守る。**
        #expect(store.editedText.hasSuffix("こちらの編集。"))
        #expect(store.isDirty)
        #expect(store.changedOutside)       // 印だけ立つ
    }

    @Test @MainActor func movingTheYearDoesNotLookLikeAnOutsideChange() async throws {
        // 年を動かすと 世界.yaml が書かれ、監視が全体を索引し直す（設計書 4.2）。
        // 節点のファイルは変わっていないので、偽の警告を出してはいけない。
        let v = try TestVault.copiedSample()
        let store = VaultStore(vault: v)
        await store.load()
        await store.stopWatchingForTest()   // 索引し直すのはこの試験だけ
        store.select("場所/鉄鎚亭.md")
        try await until { store.raw.contains("鉄鎚亭") }
        store.editedText = store.editedText + "\nこちらの編集。"
        store.writeDelay = .milliseconds(20)
        store.setYear(404)
        try await until { (try? String(contentsOf: v.appendingPathComponent("世界.yaml"), encoding: .utf8))?
                            .contains("現在: 404") == true }
        await store.rebuildForTest()
        #expect(store.editedText.hasSuffix("こちらの編集。"))
        #expect(store.isDirty)
        #expect(!store.changedOutside)      // **偽の警告を出さない**
    }

    @Test @MainActor func aDeletedNodeStillHasItsKindCheckedOnSave() async throws {
        // 型は**パスの先頭**から引く。索引から引くと、外で消えた節点では型が nil になり、
        // `validate(kind: nil)` が 世界.md 扱いで素通しする——壊れた front matter のまま
        // 消えた場所へ書き戻せてしまう。
        let v = try TestVault.copiedSample()
        let store = VaultStore(vault: v)
        await store.load()
        await store.stopWatchingForTest()   // 索引し直すのはこの試験だけ
        store.select("場所/鉄鎚亭.md")
        try await until { store.raw.contains("鉄鎚亭") }
        // 先に編集しておく。編集を抱えていないと、消えた節点は読み込みに失敗した扱いで
        // 下書きが作れない（課題 2 の守り）——保存の検証まで届かない。
        store.editedText += "\nこちらの編集。"
        let url = v.appendingPathComponent("場所/鉄鎚亭.md")
        try FileManager.default.removeItem(at: url)
        await store.reindexForTest([url])
        store.editedText = "front matter を消してしまった。"
        #expect(!store.save())                                          // **書かない**
        #expect(!FileManager.default.fileExists(atPath: url.path))      // 作り直してもいない
        let reason = try #require(store.saveError)
        #expect(reason.hasPrefix("1 行目"))
    }

    @Test @MainActor func savingAfterAnOutsideChangeOverwritesIt() async throws {
        // 設計書 8.3。⌘S はそのまま上書きする。
        let v = try TestVault.copiedSample()
        let store = VaultStore(vault: v)
        await store.load()
        await store.stopWatchingForTest()   // 索引し直すのはこの試験だけ
        store.select("場所/鉄鎚亭.md")
        try await until { store.raw.contains("鉄鎚亭") }
        store.editedText = store.editedText.replacingOccurrences(of: "種別: 宿", with: "種別: 旅籠")
        let url = v.appendingPathComponent("場所/鉄鎚亭.md")
        try (try String(contentsOf: url, encoding: .utf8) + "\n外で足した。")
            .write(to: url, atomically: true, encoding: .utf8)
        await store.reindexForTest([url])
        #expect(store.changedOutside)
        #expect(store.save())
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("種別: 旅籠"))
        #expect(!text.contains("外で足した。"))   // こちらの内容で上書きした
        #expect(!store.changedOutside)           // 印は下りる
    }

    @Test @MainActor func aDeletedNodeKeepsTheSelectionWhileTheEditIsUnsaved() async throws {
        // **外で消されても、抱えている編集は捨てない。**⌘S で書き戻せる場所に留める。
        let v = try TestVault.copiedSample()
        let store = VaultStore(vault: v)
        await store.load()
        await store.stopWatchingForTest()   // 索引し直すのはこの試験だけ
        store.select("場所/鉄鎚亭.md")
        try await until { store.raw.contains("鉄鎚亭") }
        store.editedText += "\nこちらの編集。"
        let url = v.appendingPathComponent("場所/鉄鎚亭.md")
        try FileManager.default.removeItem(at: url)
        await store.reindexForTest([url])
        #expect(store.selected == "場所/鉄鎚亭.md")     // **選択を保つ**
        #expect(store.isDirty)
        #expect(store.changedOutside)
        #expect(store.editedText.hasSuffix("こちらの編集。"))
        #expect(store.canEdit)                         // 読み込みは失敗しているが直せる
        // ⌘S で消えた場所へ書き戻せる。それが利用者の望む復旧である。
        #expect(store.save())
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test @MainActor func aDeletedNodeWithNothingUnsavedDropsTheDraftToo() async throws {
        // 保存した直後に外で消される経路。**`save()` は綺麗な下書きを残すので、ここへ来る。**
        // 選択だけ外して下書きを残すと、画面は概要なのに ⌘S が旧節点へ書く。
        let v = try TestVault.copiedSample()
        let store = VaultStore(vault: v)
        await store.load()
        await store.stopWatchingForTest()   // 索引し直すのはこの試験だけ
        store.select("場所/鉄鎚亭.md")
        try await until { store.raw.contains("鉄鎚亭") }
        store.editedText += "\nこちらの編集。"
        #expect(store.save())
        #expect(!store.isDirty)
        #expect(store.draft != nil)                    // 綺麗な下書きが残っている
        let url = v.appendingPathComponent("場所/鉄鎚亭.md")
        try FileManager.default.removeItem(at: url)
        await store.reindexForTest([url])
        #expect(store.selected == nil)                 // 概要へ戻る
        #expect(store.draft == nil)                    // **下書きも一緒に捨てる**
        #expect(!store.changedOutside)
    }

    @Test @MainActor func revertingTheTextAfterADeletionDoesNotLockTheEditor() async throws {
        // レビューで見つかった経路: 壊れているが読める原稿を原文で開く → 一文字足す →
        // 外で削除 → 足した一文字を消して基準へ戻す。基準へ戻った瞬間 isDirty は偽に
        // なるが、消えた節点をわざと抱えている印（changedOutside）はそこでは下りない
        // ——`save()` が書き終えるまで下りない。**`isDirty` だけを見ると、ここで
        // 欄が閉じ、次の一打も setter に拒まれて行き止まりになる。**
        let v = try TestVault.copiedSample()
        try "---\n名前: 壊れ\n期間: これは年ではない\n---\n本文\n"
            .write(to: v.appendingPathComponent("場所/壊れ.md"), atomically: true, encoding: .utf8)
        let store = VaultStore(vault: v)
        await store.load()
        await store.stopWatchingForTest()   // 索引し直すのはこの試験だけ
        store.select("場所/壊れ.md")
        try await until { store.raw.contains("壊れ") }
        #expect(store.isBroken)
        let base = store.editedText
        store.editedText = base + "x"
        let url = v.appendingPathComponent("場所/壊れ.md")
        try FileManager.default.removeItem(at: url)
        await store.reindexForTest([url])
        #expect(store.changedOutside)
        #expect(store.canEdit)
        // 足した一文字を消して、基準へ戻す。
        store.editedText = base
        #expect(!store.isDirty)
        // **欄はここで閉じない。**行き止まりにしてはいけない。
        #expect(store.canEdit)
        // 次の一打も届く——setter が拒んでいない証拠。
        store.editedText = base + "x"
        #expect(store.editedText.hasSuffix("x"))
        // front matter を直して、消えた場所へ書き戻す。それが復旧の目的である。
        store.editedText = "---\n名前: 壊れ\n種別: 場所\n期間: [1, 現在]\n---\n直した。\n"
        #expect(store.save())
        #expect(FileManager.default.fileExists(atPath: url.path))
        let saved = try String(contentsOf: url, encoding: .utf8)
        #expect(saved.contains("直した"))
    }

    @Test @MainActor func aFailedReloadDoesNotOfferAnEmptyEditableDraft() async throws {
        // 世界.md が外で非UTF-8へ書き換わったとき、読み込みは失敗する。その空文字を
        // 「外の内容」として基準へ丸めてはいけない——綺麗な下書きだけで編集可能になり、
        // 理由の出ないまま⌘Sが既存のファイルを打ち直した分だけで潰してしまう。
        let v = try TestVault.copiedSample()
        let store = VaultStore(vault: v)
        await store.load()
        await store.stopWatchingForTest()
        store.select(nil)
        store.editedText = "灰海は塩と鉄の海である。"
        #expect(store.save())
        #expect(!store.isDirty)                        // 綺麗な下書きが残った
        let url = v.appendingPathComponent("世界.md")
        // 有効な UTF-8 として読めないバイト列で外から上書きする。
        let corrupted = Data([0xFF, 0xFE, 0x00, 0x80])
        try corrupted.write(to: url)
        await store.rebuildForTest()
        #expect(!store.canEdit)                        // 空欄を編集可能にしない
        #expect(store.textError != nil)                // 読めなかった理由が立っている
        // **下書きが空文字で置き換わっていない。**ここが「理由の出ない編集可能な空欄」の
        // 実体である——`canEdit` が誤って真になるのも、下書きの中身が空にすり替わって
        // いるからこそ起きる。UI は disabled にするが、`save()` は `canEdit` を見ない
        // （`canSave` だけを見る）ので、disk 上のバイト列そのものでの検査は、素の
        // `save()` 呼び出しだけでは常に無変化になり、この壊れを見分けられない
        // （下書きは空文字どうしで綺麗なままなので、書くものが無いと判定される）。
        #expect(store.editedText == "灰海は塩と鉄の海である。")
        // 書くものが無いと判定されるので、素の save() はディスクへ触れない。
        store.save()
        #expect(try Data(contentsOf: url) == corrupted)
        // **実害の経路はここである。**空欄が出たあと、利用者は打ってから ⌘S する。
        // 打てば下書きが汚れ、`canSave` が真になり、読めなかったファイルが
        // 打ち込んだ分だけで潰される。store 側で書き込み自体を断る。
        store.editedText = "打ち直した。"
        store.save()
        #expect(try Data(contentsOf: url) == corrupted)   // 元のバイト列のまま
        #expect(!store.isDirty)
    }

    @Test @MainActor func movingWithNothingUnsavedGoesStraightThrough() async throws {
        let store = VaultStore(vault: try TestVault.copiedSample())
        await store.load()
        store.requestSelect("場所/鉄鎚亭.md")
        #expect(store.selected == "場所/鉄鎚亭.md")
        #expect(store.pendingPassage == nil)
    }

    @Test @MainActor func movingWithUnsavedWorkAsksFirst() async throws {
        let store = VaultStore(vault: try TestVault.copiedSample())
        await store.load()
        store.select("場所/鉄鎚亭.md")
        try await until { store.raw.contains("鉄鎚亭") }
        store.editedText += "\nこちらの編集。"
        store.requestSelect("場所/職人街.md")
        #expect(store.pendingPassage == .node("場所/職人街.md"))
        #expect(store.selected == "場所/鉄鎚亭.md")     // まだ移っていない
    }

    @Test @MainActor func savingAndGoingMovesAndKeepsTheEdit() async throws {
        let v = try TestVault.copiedSample()
        let store = VaultStore(vault: v)
        await store.load()
        store.select("場所/鉄鎚亭.md")
        try await until { store.raw.contains("鉄鎚亭") }
        store.editedText += "\nこちらの編集。"
        store.requestSelect("場所/職人街.md")
        store.passageSaveAndGo()
        #expect(store.selected == "場所/職人街.md")
        #expect(store.pendingPassage == nil)
        let text = try String(contentsOf: v.appendingPathComponent("場所/鉄鎚亭.md"), encoding: .utf8)
        #expect(text.hasSuffix("こちらの編集。"))
    }

    @Test @MainActor func savingAndGoingStaysPutWhenTheSaveFails() async throws {
        // **通らなければ移らず、問いを出し直す。**
        let store = VaultStore(vault: try TestVault.copiedSample())
        await store.load()
        store.select("場所/鉄鎚亭.md")
        try await until { store.raw.contains("鉄鎚亭") }
        store.editedText = "front matter を壊した。"
        store.requestSelect("場所/職人街.md")
        store.passageSaveAndGo()
        #expect(store.selected == "場所/鉄鎚亭.md")
        #expect(store.pendingPassage == .node("場所/職人街.md"))   // 問いは残る
        #expect(store.saveError != nil)
        #expect(store.isDirty)
    }

    @Test @MainActor func discardingThrowsTheEditAwayAndMoves() async throws {
        let v = try TestVault.copiedSample()
        let store = VaultStore(vault: v)
        await store.load()
        store.select("場所/鉄鎚亭.md")
        try await until { store.raw.contains("鉄鎚亭") }
        let before = try String(contentsOf: v.appendingPathComponent("場所/鉄鎚亭.md"), encoding: .utf8)
        store.editedText += "\nこちらの編集。"
        store.requestSelect("場所/職人街.md")
        store.passageDiscardAndGo()
        #expect(store.selected == "場所/職人街.md")
        #expect(store.pendingPassage == nil)
        #expect(!store.isDirty)
        let after = try String(contentsOf: v.appendingPathComponent("場所/鉄鎚亭.md"), encoding: .utf8)
        #expect(after == before)          // ファイルは触っていない
    }

    @Test @MainActor func cancellingKeepsEverything() async throws {
        let store = VaultStore(vault: try TestVault.copiedSample())
        await store.load()
        store.select("場所/鉄鎚亭.md")
        try await until { store.raw.contains("鉄鎚亭") }
        store.editedText += "\nこちらの編集。"
        store.requestSelect("場所/職人街.md")
        store.passageCancel()
        #expect(store.selected == "場所/鉄鎚亭.md")
        #expect(store.pendingPassage == nil)
        #expect(store.isDirty)
        #expect(store.editedText.hasSuffix("こちらの編集。"))
    }

    @Test @MainActor func goingToTheParentPassesThroughTheSameGate() async throws {
        let store = VaultStore(vault: try TestVault.copiedSample())
        await store.load()
        store.select("場所/鉄鎚亭.md")
        try await until { store.raw.contains("鉄鎚亭") }
        store.editedText += "\nこちらの編集。"
        store.goToParent()
        #expect(store.pendingPassage == .node("場所/職人街.md"))
        #expect(store.selected == "場所/鉄鎚亭.md")
    }

    @Test @MainActor func closingWithNothingUnsavedIsAllowed() async throws {
        let store = VaultStore(vault: try TestVault.copiedSample())
        await store.load()
        #expect(store.requestClose())          // そのまま閉じてよい
        #expect(store.pendingPassage == nil)
    }

    @Test @MainActor func closingWithUnsavedWorkIsHeldAndAsks() async throws {
        let store = VaultStore(vault: try TestVault.copiedSample())
        await store.load()
        store.select("場所/鉄鎚亭.md")
        try await until { store.raw.contains("鉄鎚亭") }
        store.editedText += "\nこちらの編集。"
        #expect(!store.requestClose())         // **閉じさせない**
        #expect(store.pendingPassage == .closeWindow)
    }

    @Test @MainActor func savingThenClosingWritesTheFile() async throws {
        let v = try TestVault.copiedSample()
        let store = VaultStore(vault: v)
        await store.load()
        store.select("場所/鉄鎚亭.md")
        try await until { store.raw.contains("鉄鎚亭") }
        store.editedText += "\nこちらの編集。"
        #expect(!store.requestClose())
        store.passageSaveAndGo()
        #expect(store.pendingPassage == nil)
        #expect(!store.isDirty)
        let text = try String(contentsOf: v.appendingPathComponent("場所/鉄鎚亭.md"), encoding: .utf8)
        #expect(text.hasSuffix("こちらの編集。"))
    }

    @Test @MainActor func cancellingTheCloseKeepsTheEdit() async throws {
        let store = VaultStore(vault: try TestVault.copiedSample())
        await store.load()
        store.select("場所/鉄鎚亭.md")
        try await until { store.raw.contains("鉄鎚亭") }
        store.editedText += "\nこちらの編集。"
        #expect(!store.requestClose())
        store.passageCancel()
        #expect(store.pendingPassage == nil)
        #expect(store.isDirty)
    }

    @Test @MainActor func aFailedSaveDoesNotLetTheWindowClose() async throws {
        let store = VaultStore(vault: try TestVault.copiedSample())
        await store.load()
        store.select("場所/鉄鎚亭.md")
        try await until { store.raw.contains("鉄鎚亭") }
        store.editedText = "front matter を壊した。"
        #expect(!store.requestClose())
        store.passageSaveAndGo()
        #expect(store.pendingPassage == .closeWindow)   // 問いは残る
        #expect(!store.wantsClose)                      // 閉じてよいとは言っていない
        #expect(store.saveError != nil)
    }

    @Test @MainActor func discardingLetsTheWindowClose() async throws {
        let store = VaultStore(vault: try TestVault.copiedSample())
        await store.load()
        store.select("場所/鉄鎚亭.md")
        try await until { store.raw.contains("鉄鎚亭") }
        store.editedText += "\nこちらの編集。"
        #expect(!store.requestClose())
        store.passageDiscardAndGo()
        #expect(store.wantsClose)                       // 橋がこれを見て閉じる
        #expect(!store.isDirty)
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

/// **`OpenVaults` はプロセス全体で一つの帳面である。**Swift Testing は既定でテストを
/// 並行に走らせるので、`await` のたびに互いの帳面を消し合う。ここだけ直列にする。
/// 帳面に触るのはこの三本だけなので、他の suite と並行に走っても構わない。
@Suite(.serialized) struct OpenVaultsTests {
    @Test @MainActor func theQuitGateFindsTheWindowHoldingUnsavedWork() async throws {
        OpenVaults.forgetAllForTest()
        let clean = VaultStore(vault: try TestVault.copiedSample())
        let dirty = VaultStore(vault: try TestVault.copiedSample())
        await clean.load()
        await dirty.load()
        OpenVaults.register(clean, window: nil)
        OpenVaults.register(dirty, window: nil)
        #expect(OpenVaults.firstDirty == nil)          // まだ誰も編集していない
        dirty.select("場所/鉄鎚亭.md")
        try await until { dirty.raw.contains("鉄鎚亭") }
        dirty.editedText += "\nこちらの編集。"
        #expect(OpenVaults.firstDirty?.store === dirty)  // **抱えている窓を見つける**
    }
    @Test @MainActor func aClosedWindowIsNoLongerAskedOnQuit() async throws {
        OpenVaults.forgetAllForTest()
        do {
            let store = VaultStore(vault: try TestVault.copiedSample())
            await store.load()
            OpenVaults.register(store, window: nil)
            store.select("場所/鉄鎚亭.md")
            try await until { store.raw.contains("鉄鎚亭") }
            store.editedText += "\nこちらの編集。"
            #expect(OpenVaults.firstDirty != nil)
            OpenVaults.forget(store)
        }
        // **閉じた窓の分まで終了を止めない。**
        #expect(OpenVaults.firstDirty == nil)
    }
    @Test @MainActor func theQuitGateAsksTheStoreAndStopsTheQuit() async throws {
        OpenVaults.forgetAllForTest()
        let store = VaultStore(vault: try TestVault.copiedSample())
        await store.load()
        OpenVaults.register(store, window: nil)
        store.select("場所/鉄鎚亭.md")
        try await until { store.raw.contains("鉄鎚亭") }
        store.editedText += "\nこちらの編集。"
        #expect(!OpenVaults.mayQuit())                 // **終了させない**
        #expect(store.pendingPassage == .closeWindow)  // 三択が出ている
        store.passageDiscardAndGo()
        #expect(OpenVaults.mayQuit())                  // 答えたら終われる
    }
}
