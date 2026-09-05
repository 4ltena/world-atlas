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
}
