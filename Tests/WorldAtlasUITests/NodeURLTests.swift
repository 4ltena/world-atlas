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
