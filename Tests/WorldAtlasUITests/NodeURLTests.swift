import Foundation
import Testing
@testable import WorldAtlasUI

@Suite struct NodeURLTests {
    @Test(arguments: [
        "場所/職人街.md",
        "書籍/灰海誌 第一巻.md",
        "出来事/大火(588).md",
        "法律/塩の法 [改].md",
        "人物/A#B?C.md",
    ])
    func roundTrips(_ path: String) {
        #expect(NodeURL.path(from: NodeURL.make(path: path)) == path)
    }

    @Test func slashIsOneSegmentNotTwo() {
        // 相対パスは丸ごと一区画に入れる。区切りの / も符号化する。
        #expect(NodeURL.make(path: "場所/職人街.md").absoluteString.contains("%2F"))
    }

    @Test func otherSchemesAreNotOurs() {
        #expect(NodeURL.path(from: URL(string: "https://example.com/場所/職人街.md")!) == nil)
        #expect(NodeURL.path(from: URL(string: "worldatlas://year/500")!) == nil)
    }
}

@Suite("リンクが運ぶ、辿り着いた名前")
struct NodeURLArrivalTests {
    @Test("名前を付けて作ると、取り出せる")
    func roundTrip() throws {
        let u = NodeURL.make(path: "場所/エルデン邑.md", arrivedAs: "エルデン市")
        #expect(NodeURL.path(from: u) == "場所/エルデン邑.md")
        #expect(NodeURL.arrivedName(from: u) == "エルデン市")
    }

    @Test("名前を付けなければ nil。これまでの URL と同じ形である")
    func none() throws {
        let u = NodeURL.make(path: "場所/エルデン邑.md")
        #expect(NodeURL.arrivedName(from: u) == nil)
        #expect(u.absoluteString == NodeURL.make(path: "場所/エルデン邑.md").absoluteString)
    }

    @Test("記号を含む名前でも壊れない")
    func symbols() throws {
        let u = NodeURL.make(path: "場所/a.md", arrivedAs: "帝国（北）#1")
        #expect(NodeURL.path(from: u) == "場所/a.md")
        #expect(NodeURL.arrivedName(from: u) == "帝国（北）#1")
    }

    @Test("濁点付きの仮名は、パスと同じく結合形へそろえる")
    func nfc() throws {
        let u = NodeURL.make(path: "場所/a.md", arrivedAs: "ヴォルフ商会")
        #expect(NodeURL.arrivedName(from: u) == "ヴォルフ商会")
    }
}
