import Testing
@testable import WorldAtlasCore

@Suite struct WikiLinksTests {
    @Test func extractsInOrderWithoutDuplicates() {
        let body = "[[職人街]]の[[鉄鎚亭]]と[[職人街]]。"
        #expect(WikiLinks.targets(in: body) == ["職人街", "鉄鎚亭"])
    }
    @Test func ignoresEmptyAndNested() {
        #expect(WikiLinks.targets(in: "[[]] と [[a]]") == ["a"])
    }
    @Test func trimsWhitespace() {
        #expect(WikiLinks.targets(in: "[[ 石橋 ]]") == ["石橋"])
    }
    @Test func noLinks() { #expect(WikiLinks.targets(in: "本文だけ") == []) }
    @Test func countsKeepOrderAndCountRepeats() {
        let c = WikiLinks.counts(in: "[[職人街]]の[[鉄鎚亭]]と[[職人街]]。")
        #expect(c.map(\.target) == ["職人街", "鉄鎚亭"])
        #expect(c.map(\.count) == [2, 1])
    }
}
