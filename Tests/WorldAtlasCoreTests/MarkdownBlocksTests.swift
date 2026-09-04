import Testing
@testable import WorldAtlasCore

@Suite struct MarkdownBlocksTests {
    @Test func splitsParagraphsHeadingsAndLists() {
        let body = """
        一段目。
        続き。

        ## 城壁

        - 一つ
        - 二つ

        三段目。
        """
        let blocks = MarkdownBlocks.split(body)
        #expect(blocks == [
            .paragraph("一段目。\n続き。"),
            .heading(level: 2, text: "城壁"),
            .list(["一つ", "二つ"]),
            .paragraph("三段目。"),
        ])
    }
    @Test func multipleBlankLinesCollapse() {
        #expect(MarkdownBlocks.split("a\n\n\n\nb") == [.paragraph("a"), .paragraph("b")])
    }
    @Test func emptyBodyGivesNoBlocks() { #expect(MarkdownBlocks.split("") == []) }
    @Test func crlfIsNormalized() {
        #expect(MarkdownBlocks.split("a\r\n\r\nb\r\n") == [.paragraph("a"), .paragraph("b")])
    }
    @Test func headingLevelOneToThree() {
        #expect(MarkdownBlocks.split("# 大\n\n### 小") == [.heading(level: 1, text: "大"), .heading(level: 3, text: "小")])
    }
}
