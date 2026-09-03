import Testing
@testable import WorldAtlasCore

@Suite struct FrontMatterSplitTests {
    @Test func splitsFencedYamlFromBody() {
        let text = "---\n名前: 職人街\n種別: 区\n---\n本文の一行目\n二行目\n"
        let s = FrontMatter.split(text)
        #expect(s?.yaml == "名前: 職人街\n種別: 区\n")
        #expect(s?.body == "本文の一行目\n二行目\n")
        #expect(s?.bodyLine == 5)
    }
    @Test func returnsNilWithoutOpeningFence() {
        #expect(FrontMatter.split("名前: 職人街\n") == nil)
    }
    @Test func returnsNilWithoutClosingFence() {
        #expect(FrontMatter.split("---\n名前: 職人街\n") == nil)
    }
    @Test func acceptsCRLF() {
        let s = FrontMatter.split("---\r\n名前: 職人街\r\n---\r\n本文\r\n")
        #expect(s?.yaml == "名前: 職人街\n")
        #expect(s?.body == "本文\n")
    }
    @Test func emptyBodyIsAllowed() {
        let s = FrontMatter.split("---\n名前: 職人街\n---\n")
        #expect(s?.body == "")
    }
}
