import Testing
import WorldAtlasCore
@testable import WorldAtlasUI

@Suite struct DraftTests {
    /// 見本の vault の鉄鎚亭と同じ形。
    let sound = """
    ---
    名前: 鉄鎚亭
    種別: 宿
    期間: [322, 588]
    ---
    二階の広間で徒弟の年季証文が交わされた。
    """

    @Test func aNewDraftIsClean() {
        let d = Draft(path: "場所/鉄鎚亭.md", base: sound)
        #expect(!d.isDirty)
        #expect(d.text == sound)
    }

    @Test func editingMakesItDirty() {
        var d = Draft(path: "場所/鉄鎚亭.md", base: sound)
        d.text += "\n追記。"
        #expect(d.isDirty)
    }

    @Test func typingAndUndoingLeavesItClean() {
        // 文字列が元に戻れば汚れも落ちる。差分ではなく値で見ている。
        var d = Draft(path: "場所/鉄鎚亭.md", base: sound)
        d.text += "x"
        d.text.removeLast()
        #expect(!d.isDirty)
    }

    @Test func savingMovesTheBaseToTheCurrentText() {
        var d = Draft(path: "場所/鉄鎚亭.md", base: sound)
        d.text += "\n追記。"
        let after = d.saved()
        #expect(!after.isDirty)
        #expect(after.base == after.text)
        #expect(after.text.hasSuffix("追記。"))
    }

    @Test func soundFrontMatterPasses() {
        #expect(Draft(path: "場所/鉄鎚亭.md", base: sound).validate(kind: .place) == nil)
    }

    @Test func missingFrontMatterIsRejectedWithALine() throws {
        let d = Draft(path: "場所/鉄鎚亭.md", base: "front matter がありません。")
        let e = try #require(d.validate(kind: .place))
        #expect(e.line == 1)
        #expect(e.message.contains("front matter"))
    }

    @Test func aBrokenValueIsRejected() throws {
        var d = Draft(path: "場所/鉄鎚亭.md", base: sound)
        d.text = d.text.replacingOccurrences(of: "期間: [322, 588]", with: "期間: 322")
        #expect(d.validate(kind: .place) != nil)
    }

    @Test func theWorldFileIsNotChecked() {
        // 世界.md は front matter を持たない。素通しする（設計書 4.1）。
        let d = Draft(path: nil, base: "世界全体の概要をここに書く。")
        #expect(d.validate(kind: nil) == nil)
    }

    @Test func anUneditedDraftFollowsTheOutsideChange() {
        let d = Draft(path: "場所/鉄鎚亭.md", base: sound)
        let (next, outside) = d.merging(external: sound + "\n外で足した。")
        #expect(next.text.hasSuffix("外で足した。"))
        #expect(next.base == next.text)
        #expect(!next.isDirty)
        #expect(!outside)          // 編集していないので、知らせることは無い
    }

    @Test func anEditedDraftIsHeldAndTheChangeIsFlagged() {
        var d = Draft(path: "場所/鉄鎚亭.md", base: sound)
        d.text += "\nこちらの編集。"
        let (next, outside) = d.merging(external: sound + "\n外で足した。")
        #expect(next.text.hasSuffix("こちらの編集。"))   // **編集中の文字列を守る**
        #expect(next.base == d.base)                    // 基準は動かさない
        #expect(outside)                                // 印だけ立てる
    }

    @Test func theSameContentIsNotAnOutsideChange() {
        // 自分が書いたものを読み直しただけ。年カーソルを動かすと 世界.yaml が書かれ、
        // 監視が全体を索引し直すので、この経路は毎回通る。
        var d = Draft(path: "場所/鉄鎚亭.md", base: sound)
        d.text += "\nこちらの編集。"
        let (next, outside) = d.merging(external: sound)
        #expect(!outside)
        #expect(next == d)
    }
}
