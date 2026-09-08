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

@Suite("名前の有効期間")
struct NamePeriodTests {
    /// 見本の エルデン邑 と同じ形。保存名と別名二つ。
    private func elden() -> Node {
        Node(name: "エルデン邑", kind: .place, category: "都市", from: 96, to: nil,
             aliases: [Alias(from: 318, name: "王都エルデン"),
                       Alias(from: 501, name: "エルデン市")])
    }

    @Test("保存名は、最初の別名の前年で終わる")
    func savedName() throws {
        let p = try #require(elden().period(ofName: "エルデン邑"))
        #expect(p.from == 96)
        #expect(p.to == 317)
    }

    @Test("間の別名は、次の別名の前年で終わる")
    func middleAlias() throws {
        let p = try #require(elden().period(ofName: "王都エルデン"))
        #expect(p.from == 318)
        #expect(p.to == 500)
    }

    @Test("最後の別名は、節点の終わりで閉じる。終わりが無ければ nil")
    func lastAlias() throws {
        let p = try #require(elden().period(ofName: "エルデン市"))
        #expect(p.from == 501)
        #expect(p.to == nil)
    }

    @Test("持っていない名前は nil")
    func unknown() {
        #expect(elden().period(ofName: "石橋") == nil)
    }

    @Test("別名の順が front matter で入れ替わっていても同じ")
    func unordered() throws {
        let n = Node(name: "エルデン邑", kind: .place, category: "都市", from: 96, to: nil,
                     aliases: [Alias(from: 501, name: "エルデン市"),
                               Alias(from: 318, name: "王都エルデン")])
        let p = try #require(n.period(ofName: "王都エルデン"))
        #expect(p.to == 500)
    }

    @Test("節点の開始年以前に別名が始まっていると、保存名は一度も出ない")
    func savedNameNeverShown() {
        let n = Node(name: "旧名", kind: .polity, category: "勢力", from: 100, to: 200,
                     aliases: [Alias(from: 100, name: "新名")])
        #expect(n.period(ofName: "旧名") == nil)
    }

    @Test("終わりのある節点の最後の別名は、その終わりで閉じる")
    func closedNode() throws {
        let n = Node(name: "北ヴェルダ王国", kind: .polity, category: "勢力", from: 412, to: 596,
                     aliases: [Alias(from: 501, name: "北ヴェルダ共和国")])
        let p = try #require(n.period(ofName: "北ヴェルダ共和国"))
        #expect(p.from == 501)
        #expect(p.to == 596)
    }

    @Test("同じ名前へ二度戻るときは、新しいほうを採る")
    func repeated() throws {
        let n = Node(name: "本名", kind: .polity, category: "勢力", from: 1, to: 300,
                     aliases: [Alias(from: 100, name: "別名"),
                               Alias(from: 200, name: "本名")])
        let p = try #require(n.period(ofName: "本名"))
        #expect(p.from == 200)
        #expect(p.to == 300)
    }

    @Test("節点の開始より前に始まる別名は、開始年から効く")
    func aliasBeforeNodeStart() throws {
        let n = Node(name: "甲", kind: .polity, category: "勢力", from: 100, to: 200,
                     aliases: [Alias(from: 50, name: "乙")])
        let p = try #require(n.period(ofName: "乙"))
        #expect(p.from == 100)          // 50 ではない
        #expect(p.to == 200)
        // 保存名は一度も出ない。
        #expect(n.period(ofName: "甲") == nil)
    }

    @Test("節点の終わりより後に始まる別名は、一度も出ない")
    func aliasAfterNodeEnd() throws {
        let n = Node(name: "甲", kind: .polity, category: "勢力", from: 100, to: 200,
                     aliases: [Alias(from: 300, name: "乙")])
        #expect(n.period(ofName: "乙") == nil)
        let p = try #require(n.period(ofName: "甲"))
        #expect(p.to == 200)            // 299 ではない
    }

    @Test("同じ年に別名が二つあるとき、displayName が出すほうだけが期間を持つ")
    func sameYearAliases() throws {
        let n = Node(name: "甲", kind: .polity, category: "勢力", from: 1, to: 200,
                     aliases: [Alias(from: 100, name: "乙"), Alias(from: 100, name: "丙")])
        // displayName は同年なら先に書かれたほうを出す。期間はそれに従う。
        #expect(n.displayName(at: 100) == "乙")
        let p = try #require(n.period(ofName: "乙"))
        #expect(p.from == 100)
        #expect(p.to == 200)
        #expect(n.period(ofName: "丙") == nil)
        let saved = try #require(n.period(ofName: "甲"))
        #expect(saved.to == 99)
    }
}
