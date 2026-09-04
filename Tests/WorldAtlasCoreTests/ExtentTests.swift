import Testing
@testable import WorldAtlasCore

@Suite struct ExtentTests {
    func node(_ name: String, _ from: Int, _ to: Int?, marks: [Mark] = [], point: Bool = false, aliases: [Alias] = []) -> Node {
        Node(name: name, kind: .place, category: "x", from: from, to: to, isPoint: point, aliases: aliases, marks: marks)
    }

    @Test func loIsEarliestStartAndHiIsLatestOfEndsMarksAndCurrent() {
        let ex = Extent.compute(nodes: [
            node("a", 96, nil),
            node("b", 322, 588, marks: [Mark(year: 640, label: "x")]),
            node("c", 700, 700, point: true),
        ], current: 500)
        #expect(ex == Extent(lo: 96, hi: 700))
    }

    @Test func currentExtendsHi() {
        let ex = Extent.compute(nodes: [node("a", 1, 400)], current: 760)
        #expect(ex == Extent(lo: 1, hi: 760))
    }

    @Test func emptyVaultFallsBackToCurrent() {
        #expect(Extent.compute(nodes: [], current: 12) == Extent(lo: 1, hi: 12))
    }

    @Test func hiIsAtLeastLoPlusOne() {
        #expect(Extent.compute(nodes: [node("a", 5, 5, point: true)], current: 5) == Extent(lo: 5, hi: 6))
    }

    @Test func aliasYearExtendsHi() {
        let ex = Extent.compute(nodes: [
            node("a", 100, 200, aliases: [Alias(from: 300, name: "旧名")]),
        ], current: 100)
        #expect(ex == Extent(lo: 100, hi: 300))
    }
}
