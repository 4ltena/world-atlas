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

@Suite struct FrontMatterParseTests {
    let elden = """
    ---
    名前: エルデン邑
    種別: 都市
    期間: [96, 現在]
    別名:
      - [318, 王都エルデン]
      - [501, エルデン市]
    親: 北ヴェルダ
    支配:
      - [1, 412, ヴェルダ王国]
      - [596, 現在, 海都同盟]
    由来:
      - [620, 再建, 鉄鎚亭]
    出来事:
      - [318, 石橋から遷都。二重の城壁が着工]
    ---
    街道が三本交わる谷。[[職人街]]で刃物が打たれる。

    """

    @Test func parsesAllKeys() throws {
        let n = try FrontMatter.parse(elden, kind: .place)
        #expect(n.name == "エルデン邑")
        #expect(n.kind == .place)
        #expect(n.category == "都市")
        #expect(n.from == 96)
        #expect(n.to == nil)
        #expect(n.isPoint == false)
        #expect(n.aliases == [Alias(from: 318, name: "王都エルデン"), Alias(from: 501, name: "エルデン市")])
        #expect(n.parent == "北ヴェルダ")
        #expect(n.rules == [Rule(from: 1, to: 412, polity: "ヴェルダ王国"), Rule(from: 596, to: nil, polity: "海都同盟")])
        #expect(n.lineages == [Lineage(year: 620, kind: "再建", origin: "鉄鎚亭")])
        #expect(n.marks == [Mark(year: 318, label: "石橋から遷都。二重の城壁が着工")])
        #expect(n.body == "街道が三本交わる谷。[[職人街]]で刃物が打たれる。\n")
    }

    @Test func pointEventUsesYear() throws {
        let n = try FrontMatter.parse("---\n名前: 職人街の大火\n種別: 出来事\n年: 588\n---\n", kind: .event)
        #expect(n.isPoint)
        #expect(n.from == 588)
        #expect(n.to == 588)
    }

    @Test func lawMayWriteEffectInsteadOfPeriod() throws {
        let n = try FrontMatter.parse("---\n名前: 鉄の掟\n種別: 法\n効力: [590, 現在]\n---\n", kind: .law)
        #expect(n.from == 590)
        #expect(n.to == nil)
    }

    @Test func periodAndEffectTogetherIsAnError() {
        #expect(throws: FrontMatterError(line: nil, message: "期間 と 効力 は同じ意味です。どちらか一方だけ書きます")) {
            try FrontMatter.parse("---\n名前: 鉄の掟\n種別: 法\n期間: [590, 現在]\n効力: [412, 596]\n---\n", kind: .law)
        }
    }

    @Test func finiteEnd() throws {
        let n = try FrontMatter.parse("---\n名前: 鉄鎚亭\n種別: 宿\n期間: [322, 588]\n---\n", kind: .place)
        #expect(n.to == 588)
    }

    @Test func missingNameIsAnError() {
        #expect(throws: FrontMatterError(line: nil, message: "名前 がありません")) {
            try FrontMatter.parse("---\n種別: 区\n期間: [1, 2]\n---\n", kind: .place)
        }
    }

    @Test func missingPeriodAndYearIsAnError() {
        #expect(throws: FrontMatterError(line: nil, message: "期間 か 年 のどちらかが要ります")) {
            try FrontMatter.parse("---\n名前: x\n種別: 区\n---\n", kind: .place)
        }
    }

    @Test func nonIntegerYearIsAnError() {
        #expect(throws: FrontMatterError(line: nil, message: "期間 の値は整数か 現在 で書きます")) {
            try FrontMatter.parse("---\n名前: x\n種別: 区\n期間: [いつか, 現在]\n---\n", kind: .place)
        }
    }

    @Test func yamlSyntaxErrorCarriesLine() {
        do {
            _ = try FrontMatter.parse("---\n名前: x\n種別: [\n---\n", kind: .place)
            Issue.record("エラーになるべき")
        } catch {
            #expect(error.line != nil)
            #expect(error.message.hasPrefix("YAML"))
        }
    }

    @Test func noFenceIsAnError() {
        #expect(throws: FrontMatterError(line: 1, message: "先頭に --- で囲んだ front matter が要ります")) {
            try FrontMatter.parse("名前: x\n", kind: .place)
        }
    }
}
