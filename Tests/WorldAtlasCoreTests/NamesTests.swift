import Testing
@testable import WorldAtlasCore

@Suite struct NamesTests {
    let elden = Node(name: "エルデン邑", kind: .place, category: "都市", from: 96, to: nil,
                     aliases: [Alias(from: 318, name: "王都エルデン"), Alias(from: 501, name: "エルデン市")])

    @Test func savedNameBeforeAnyAlias() { #expect(elden.displayName(at: 150) == "エルデン邑") }
    @Test func aliasFromItsYear() { #expect(elden.displayName(at: 318) == "王都エルデン") }
    @Test func latestAliasWins() { #expect(elden.displayName(at: 600) == "エルデン市") }
    @Test func yearJustBeforeAlias() { #expect(elden.displayName(at: 500) == "王都エルデン") }
    @Test func unorderedAliasesStillResolve() {
        var n = elden
        n.aliases.reverse()
        #expect(n.displayName(at: 400) == "王都エルデン")
    }
}
