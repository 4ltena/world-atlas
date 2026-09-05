import Foundation
import Testing
import WorldAtlasCore
@testable import WorldAtlasStore

@Suite struct VaultCreatorTests {
    func tempDir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("wa-new-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    @Test func createsTheWorldFileAndSevenDirectories() throws {
        let d = try tempDir()
        try VaultCreator.create(at: d, worldName: "新しい世界", calendarName: "共通暦")
        for k in Kind.allCases {
            var isDir: ObjCBool = false
            #expect(FileManager.default.fileExists(atPath: d.appendingPathComponent(k.rawValue).path, isDirectory: &isDir))
            #expect(isDir.boolValue)
        }
        let w = try WorldFile.parse(String(contentsOf: d.appendingPathComponent("世界.yaml"), encoding: .utf8))
        #expect(w == World(name: "新しい世界", baseCalendar: "共通暦",
                           calendars: [CalendarDef(name: "共通暦", offset: 0)], current: 1))
    }

    @Test func theNewVaultOpensAsAnEmptyIndex() async throws {
        let d = try tempDir()
        try VaultCreator.create(at: d, worldName: "新しい世界", calendarName: "共通暦")
        let s = try await Indexer(vault: d).rebuild()
        #expect(s.world.name == "新しい世界")
        #expect(s.nodes.isEmpty)
        #expect(s.ignoredDirectories == 0)
    }

    @Test func existingFilesAreLeftAlone() throws {
        let d = try tempDir()
        try FileManager.default.createDirectory(at: d.appendingPathComponent("場所"), withIntermediateDirectories: true)
        let keep = d.appendingPathComponent("場所/既にある.md")
        try "手で書いた本文".write(to: keep, atomically: true, encoding: .utf8)
        try "覚え書き".write(to: d.appendingPathComponent("メモ.txt"), atomically: true, encoding: .utf8)

        try VaultCreator.create(at: d, worldName: "新しい世界", calendarName: "共通暦")

        #expect(try String(contentsOf: keep, encoding: .utf8) == "手で書いた本文")
        #expect(FileManager.default.fileExists(atPath: d.appendingPathComponent("メモ.txt").path))
    }

    @Test func aDirectoryThatIsAlreadyAVaultIsRefused() throws {
        let d = try tempDir()
        try VaultCreator.create(at: d, worldName: "先の世界", calendarName: "共通暦")
        #expect(throws: VaultCreator.Failure.self) {
            try VaultCreator.create(at: d, worldName: "後の世界", calendarName: "別の暦")
        }
        // 断ったのだから、前の世界のままである。
        let w = try WorldFile.parse(String(contentsOf: d.appendingPathComponent("世界.yaml"), encoding: .utf8))
        #expect(w.name == "先の世界")
    }

    @Test func aMissingDirectoryIsCreated() throws {
        let d = try tempDir().appendingPathComponent("まだ無い")
        try VaultCreator.create(at: d, worldName: "新しい世界", calendarName: "共通暦")
        #expect(FileManager.default.fileExists(atPath: d.appendingPathComponent("世界.yaml").path))
    }

    @Test func namesWithYamlIndicatorsSurviveTheRoundTrip() throws {
        let d = try tempDir()
        try VaultCreator.create(at: d, worldName: "灰: 海", calendarName: "帝国暦, 改")
        let w = try WorldFile.parse(String(contentsOf: d.appendingPathComponent("世界.yaml"), encoding: .utf8))
        #expect(w.name == "灰: 海")
        #expect(w.baseCalendar == "帝国暦, 改")
    }
}
