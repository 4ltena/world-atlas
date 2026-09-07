import Foundation
import Testing
import WorldAtlasCore
@testable import WorldAtlasStore

@Suite struct NodeCreatorTests {
    private func tempVault() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("node-creator-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func aPlaceGetsAPeriod() throws {
        let v = try tempVault()
        let path = try NodeCreator.create(in: v, kind: .place, name: "塩蔵通り", year: 500)
        #expect(path == "場所/塩蔵通り.md")
        let text = try String(contentsOf: v.appendingPathComponent(path), encoding: .utf8)
        // 名前の引用の要否は WorldFile.scalar が決める。ここでは解析後の値で比べ、
        // 引用してもしなくても正しい実装であれば通るようにする。
        let node = try FrontMatter.parse(text, kind: .place)
        #expect(node.name == "塩蔵通り")
        #expect(text.contains("種別: 場所"))
        #expect(text.contains("期間: [500, 現在]"))
    }

    @Test func anEventGetsASingleYear() throws {
        // 出来事は 年。期間と同時には書けない（Stage 1 の FrontMatter）。
        let v = try tempVault()
        let path = try NodeCreator.create(in: v, kind: .event, name: "塩の乱", year: 612)
        let text = try String(contentsOf: v.appendingPathComponent(path), encoding: .utf8)
        #expect(text.contains("年: 612"))
        #expect(!text.contains("期間"))
    }

    @Test func aLawGetsAnEffectivePeriod() throws {
        let v = try tempVault()
        let path = try NodeCreator.create(in: v, kind: .law, name: "塩の条", year: 400)
        let text = try String(contentsOf: v.appendingPathComponent(path), encoding: .utf8)
        #expect(text.contains("効力: [400, 現在]"))
        #expect(!text.contains("期間"))
    }

    @Test func whatItWritesIsAcceptedByTheParser() throws {
        // **作ったものがそのまま壊れた節点になっては困る。**七つの型すべてで確かめる。
        // 種別を空にすると parse が「種別 がありません」で弾く。この試験がその番人である。
        let v = try tempVault()
        for k in Kind.allCases {
            let path = try NodeCreator.create(in: v, kind: k, name: "見本", year: 300)
            let text = try String(contentsOf: v.appendingPathComponent(path), encoding: .utf8)
            #expect(throws: Never.self) { try FrontMatter.parse(text, kind: k) }
        }
    }

    @Test func theSameFileIsRefused() throws {
        // 断るだけでなく、既にある中身が置き換わっていないことまで確かめる。
        // ここが競合の窓を閉じたかどうかの実質である。
        let v = try tempVault()
        let path = try NodeCreator.create(in: v, kind: .place, name: "塩蔵通り", year: 500)
        let before = try String(contentsOf: v.appendingPathComponent(path), encoding: .utf8)
        #expect(throws: NodeCreator.Failure.self) {
            try NodeCreator.create(in: v, kind: .place, name: "塩蔵通り", year: 999)
        }
        let after = try String(contentsOf: v.appendingPathComponent(path), encoding: .utf8)
        #expect(after == before)
    }

    @Test func theSameNameInAnotherKindIsAllowed() throws {
        // 同じ保存名は許す。索引が重複の印を付ける（設計書 4.3）。
        let v = try tempVault()
        _ = try NodeCreator.create(in: v, kind: .place, name: "トルガ", year: 500)
        let second = try NodeCreator.create(in: v, kind: .person, name: "トルガ", year: 500)
        #expect(second == "人物/トルガ.md")
    }

    @Test func anEmptyNameIsRefused() throws {
        let v = try tempVault()
        #expect(throws: NodeCreator.Failure.self) {
            try NodeCreator.create(in: v, kind: .place, name: "   ", year: 500)
        }
    }

    @Test func aNameThatWouldEscapeTheDirectoryIsRefused() throws {
        let v = try tempVault()
        for bad in ["../外", "上/下", ".隠し"] {
            #expect(throws: NodeCreator.Failure.self) {
                try NodeCreator.create(in: v, kind: .place, name: bad, year: 500)
            }
        }
    }

    @Test func surroundingSpaceIsTrimmed() throws {
        let v = try tempVault()
        let path = try NodeCreator.create(in: v, kind: .place, name: "  塩蔵通り  ", year: 500)
        #expect(path == "場所/塩蔵通り.md")
    }

    @Test func aNameThatMeansSomethingInYAMLIsQuoted() throws {
        // **素で埋め込むと壊れる名前。**# は行をコメントにして 名前 を消し、
        // 港: 北 は鍵が二つあるように見える。どちらも解析を通らない節点になる。
        let v = try tempVault()
        for name in ["#見本", "港: 北", "- 箇条", "&錨", "*参照", "100", "はい"] {
            let path = try NodeCreator.create(in: v, kind: .place, name: name, year: 500)
            let text = try String(contentsOf: v.appendingPathComponent(path), encoding: .utf8)
            let node = try FrontMatter.parse(text, kind: .place)
            #expect(node.name == name)      // **書いた名前がそのまま読み戻る**
        }
    }
}
