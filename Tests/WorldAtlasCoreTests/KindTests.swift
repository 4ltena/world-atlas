import Testing
@testable import WorldAtlasCore

@Suite struct KindTests {
    @Test func directoryNamesAreTheSevenTypes() {
        #expect(Kind.allCases.map(\.rawValue) == ["場所", "勢力", "人物", "アイテム", "書籍", "法律", "出来事"])
    }
    @Test func orderFollowsDeclaration() {
        #expect(Kind.place.order == 0)
        #expect(Kind.event.order == 6)
    }
}
