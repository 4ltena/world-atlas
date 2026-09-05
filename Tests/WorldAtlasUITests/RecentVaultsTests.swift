import Foundation
import Testing
@testable import WorldAtlasUI

@Suite struct RecentVaultsTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func roundTripsThroughJSON() {
        let list = [RecentVault(path: "/tmp/灰海", world: "灰海", openedAt: t0)]
        #expect(RecentVaults.decode(RecentVaults.encode(list)) == list)
    }

    @Test func brokenJSONGivesAnEmptyList() {
        #expect(RecentVaults.decode("これは JSON ではない").isEmpty)
        #expect(RecentVaults.decode("").isEmpty)
    }

    @Test func touchPutsTheVaultFirst() {
        var l = RecentVaults.touch([], path: "/tmp/A", world: "A", now: t0)
        l = RecentVaults.touch(l, path: "/tmp/B", world: "B", now: t0.addingTimeInterval(1))
        #expect(l.map(\.path) == ["/tmp/B", "/tmp/A"])
    }

    @Test func touchingAgainMovesItUpWithoutDuplicating() {
        var l = RecentVaults.touch([], path: "/tmp/A", world: "A", now: t0)
        l = RecentVaults.touch(l, path: "/tmp/B", world: "B", now: t0.addingTimeInterval(1))
        l = RecentVaults.touch(l, path: "/tmp/A", world: "灰海", now: t0.addingTimeInterval(2))
        #expect(l.map(\.path) == ["/tmp/A", "/tmp/B"])
        // 世界名は開き直したときのもので更新する。
        #expect(l[0].world == "灰海")
        #expect(l[0].openedAt == t0.addingTimeInterval(2))
    }

    @Test func theListStopsAtTwenty() {
        var l: [RecentVault] = []
        for i in 0..<25 { l = RecentVaults.touch(l, path: "/tmp/\(i)", world: "\(i)", now: t0.addingTimeInterval(Double(i))) }
        #expect(l.count == 20)
        #expect(l.first?.path == "/tmp/24")
        #expect(l.last?.path == "/tmp/5")
    }

    @Test func removeTakesOnlyThatOne() {
        var l = RecentVaults.touch([], path: "/tmp/A", world: "A", now: t0)
        l = RecentVaults.touch(l, path: "/tmp/B", world: "B", now: t0)
        #expect(RecentVaults.remove(l, path: "/tmp/A").map(\.path) == ["/tmp/B"])
        #expect(RecentVaults.remove(l, path: "/tmp/無い").count == 2)
    }

    @Test func oldEntriesWithoutCountsStillDecode() {
        // Stage 2 が書いた JSON には件数の鍵が無い。読めなくなってはいけない。
        let json = #"[{"path":"/tmp/a","world":"灰海","openedAt":0}]"#
        let list = RecentVaults.decode(json)
        #expect(list.count == 1)
        #expect(list[0].nodes == nil)
    }

    @Test func recordingCountsKeepsThePositionAndTheRest() {
        let list = [RecentVault(path: "/tmp/a", world: "灰海", openedAt: Date(timeIntervalSince1970: 0)),
                    RecentVault(path: "/tmp/b", world: "碧", openedAt: Date(timeIntervalSince1970: 1))]
        let out = RecentVaults.record(list, path: "/tmp/b", nodes: 41, from: 96, to: 712)
        #expect(out.map(\.path) == ["/tmp/a", "/tmp/b"])   // 並びは動かさない
        #expect(out[1].nodes == 41)
        #expect(out[1].from == 96)
        #expect(out[1].world == "碧")
    }

    @Test func recordingAnUnknownPathChangesNothing() {
        let list = [RecentVault(path: "/tmp/a", world: "灰海", openedAt: Date(timeIntervalSince1970: 0))]
        #expect(RecentVaults.record(list, path: "/tmp/z", nodes: 1, from: 1, to: 2) == list)
    }

    @Test func touchingAgainKeepsTheCountsAlreadyRecorded() {
        // 開き直した時点ではまだ索引していない。前回の件数を消してはいけない。
        var list = [RecentVault(path: "/tmp/a", world: "灰海", openedAt: Date(timeIntervalSince1970: 0))]
        list = RecentVaults.record(list, path: "/tmp/a", nodes: 41, from: 96, to: 712)
        let out = RecentVaults.touch(list, path: "/tmp/a", world: "灰海", now: Date())
        #expect(out[0].nodes == 41)
    }

    @Test func theColourIndexIsTheSameInEveryRun() {
        // 起動をまたいで同じ色になることが要件である。既知の値で固定する。
        // これが落ちたら、プロセスごとに種の変わる hashValue に戻っていないか疑う。
        #expect(RecentVaults.colorIndex(of: "/tmp/a", count: 5) == 0)
        #expect(RecentVaults.colorIndex(of: "/tmp/b", count: 5) == 1)
        #expect(RecentVaults.colorIndex(of: "/Users/kn/vaults/灰海", count: 5) == 4)
    }

    @Test func theColourIndexStaysInsideTheRange() {
        for p in ["", "a", "/x/y/z", "とても長い名前のついた世界の置き場所"] {
            let i = RecentVaults.colorIndex(of: p, count: 5)
            #expect(i >= 0 && i < 5)
        }
        // 色が一つも無いときでも落ちない。
        #expect(RecentVaults.colorIndex(of: "a", count: 0) == 0)
    }
}
