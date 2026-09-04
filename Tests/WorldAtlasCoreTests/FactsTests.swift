import Testing
@testable import WorldAtlasCore

@Suite struct FactsTests {
    let nodes: [Node] = [
        Node(name: "鉄鎚亭", kind: .place, category: "宿", from: 322, to: 588,
             marks: [Mark(year: 460, label: "厩を潰して客室を増やす")]),
        Node(name: "エルデン邑", kind: .place, category: "都市", from: 96, to: nil,
             aliases: [Alias(from: 318, name: "王都エルデン"), Alias(from: 501, name: "エルデン市")]),
        Node(name: "職人街の大火", kind: .event, category: "出来事", from: 588, to: 588, isPoint: true),
        Node(name: "六代ヴォルフ", kind: .person, category: "人物", from: 470, to: 531),
        Node(name: "継承法", kind: .law, category: "法", from: 412, to: 596),
    ]

    @Test func collectsStartsEndsRenamesMarksAndPoints() {
        let f = Facts.around(year: 588, window: 12, nodes: nodes)
        #expect(f == [
            Fact(year: 588, node: "職人街の大火", display: "職人街の大火", category: "出来事", text: ""),
            Fact(year: 588, node: "鉄鎚亭", display: "鉄鎚亭", category: "宿", text: "閉じる"),
            Fact(year: 596, node: "継承法", display: "継承法", category: "法", text: "失効"),
        ])
    }

    @Test func renameShowsOldAndNewName() {
        let f = Facts.around(year: 501, window: 0, nodes: nodes)
        #expect(f == [Fact(year: 501, node: "エルデン邑", display: "王都エルデン", category: "都市", text: "→ エルデン市")])
    }

    @Test func personVerbs() {
        let f = Facts.around(year: 470, window: 0, nodes: nodes)
        #expect(f == [Fact(year: 470, node: "六代ヴォルフ", display: "六代ヴォルフ", category: "人物", text: "生まれる")])
    }

    @Test func marksUseTheNameOfThatYear() {
        let f = Facts.around(year: 460, window: 0, nodes: nodes)
        #expect(f == [Fact(year: 460, node: "鉄鎚亭", display: "鉄鎚亭", category: "宿", text: "厩を潰して客室を増やす")])
    }

    @Test func startUsesTheNameOfThatYear() {
        let n = Node(name: "旧名", kind: .place, category: "村", from: 100, to: nil, aliases: [Alias(from: 100, name: "新名")])
        let f = Facts.around(year: 100, window: 0, nodes: [n])
        #expect(f == [
            Fact(year: 100, node: "旧名", display: "新名", category: "村", text: "成立"),
            Fact(year: 100, node: "旧名", display: "旧名", category: "村", text: "→ 新名"),
        ])
    }

    @Test func linesCarryNameCategoryAndText() {
        #expect(Facts.line(Fact(year: 588, node: "鉄鎚亭", display: "鉄鎚亭", category: "宿", text: "閉じる")) == "588: 鉄鎚亭（宿） 閉じる")
        #expect(Facts.line(Fact(year: 588, node: "職人街の大火", display: "職人街の大火", category: "出来事", text: "")) == "588: 職人街の大火（出来事）")
    }

    @Test func emptyWindowGivesNothing() {
        #expect(Facts.around(year: 200, window: 5, nodes: nodes) == [])
    }

    @Test func overviewInputIsStableText() {
        let f = Facts.around(year: 588, window: 12, nodes: nodes)
        let s = Facts.overviewInput(year: 588, window: 12, facts: f, calendar: CalendarDef(name: "帝国暦", offset: 0))
        #expect(s == """
        対象の年: 帝国暦 588 年
        範囲: 帝国暦 576 年 から 帝国暦 600 年

        588: 職人街の大火（出来事）
        588: 鉄鎚亭（宿） 閉じる
        596: 継承法（法） 失効


        """)
    }
}
