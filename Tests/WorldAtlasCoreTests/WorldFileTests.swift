import Testing
@testable import WorldAtlasCore

@Suite struct WorldFileTests {
    let yaml = """
    名前: 灰海
    基準暦: 帝国暦
    暦:
      - [帝国暦, 0]
      - [海都暦, 178]
      - [聖暦, -96]
    現在: 500
    """

    @Test func parses() throws {
        let w = try WorldFile.parse(yaml)
        #expect(w.name == "灰海")
        #expect(w.baseCalendar == "帝国暦")
        #expect(w.calendars == [CalendarDef(name: "帝国暦", offset: 0), CalendarDef(name: "海都暦", offset: 178), CalendarDef(name: "聖暦", offset: -96)])
        #expect(w.current == 500)
    }

    @Test func renderRoundTrips() throws {
        let w = try WorldFile.parse(yaml)
        let again = try WorldFile.parse(WorldFile.render(w))
        #expect(again == w)
    }

    /// 平文で書けない値を含む世界。引用せずに書き出すと読み直せないか値が変わる。
    @Test func renderQuotesUnsafeScalars() throws {
        let w = World(
            name: "海: 北",
            baseCalendar: "帝国 #1",
            calendars: [
                CalendarDef(name: "帝国 #1", offset: 0),
                CalendarDef(name: "\"引用\"", offset: 12),
                CalendarDef(name: " 前後 ", offset: -3),
                CalendarDef(name: "一覧, [と]", offset: 7),
            ],
            current: 500
        )
        #expect(try WorldFile.parse(WorldFile.render(w)) == w)
    }

    @Test func formatsYears() {
        #expect(CalendarDef(name: "帝国暦", offset: 0).format(500) == "帝国暦 500 年")
        #expect(CalendarDef(name: "海都暦", offset: 178).format(500) == "海都暦 678 年")
        #expect(CalendarDef(name: "聖暦", offset: -96).format(50) == "聖暦前 47 年")
        #expect(CalendarDef(name: "聖暦", offset: -96).format(96) == "聖暦前 1 年")
        #expect(CalendarDef(name: "聖暦", offset: -96).format(97) == "聖暦 1 年")
    }

    @Test func baseCalendarMustBeListed() {
        #expect(throws: FrontMatterError(line: nil, message: "基準暦 が 暦 の一覧にありません")) {
            try WorldFile.parse("名前: x\n基準暦: 王暦\n暦:\n  - [帝国暦, 0]\n現在: 1\n")
        }
    }

    @Test func topLevelMustBeAMapping() {
        #expect(throws: FrontMatterError(line: nil, message: "世界.yaml は 鍵: 値 の並びで書きます")) {
            try WorldFile.parse("- a\n- b\n")
        }
    }

    @Test func nameIsRequired() {
        #expect(throws: FrontMatterError(line: nil, message: "名前 がありません")) {
            try WorldFile.parse("基準暦: 帝国暦\n暦:\n  - [帝国暦, 0]\n現在: 1\n")
        }
    }

    @Test func baseCalendarKeyIsRequired() {
        #expect(throws: FrontMatterError(line: nil, message: "基準暦 がありません")) {
            try WorldFile.parse("名前: x\n暦:\n  - [帝国暦, 0]\n現在: 1\n")
        }
    }

    @Test func calendarListMustBePresentAndNonEmpty() {
        #expect(throws: FrontMatterError(line: nil, message: "暦 は - [名前, 加算する数] の並びで書きます")) {
            try WorldFile.parse("名前: x\n基準暦: 帝国暦\n現在: 1\n")
        }
    }

    @Test func calendarRowMustBeNameAndOffset() {
        #expect(throws: FrontMatterError(line: nil, message: "暦 の各行は [名前, 加算する数] で書きます")) {
            try WorldFile.parse("名前: x\n基準暦: 帝国暦\n暦:\n  - [帝国暦]\n現在: 1\n")
        }
    }

    @Test func currentMustBeAnInteger() {
        #expect(throws: FrontMatterError(line: nil, message: "現在 は整数で書きます")) {
            try WorldFile.parse("名前: x\n基準暦: 帝国暦\n暦:\n  - [帝国暦, 0]\n現在: abc\n")
        }
    }
}
