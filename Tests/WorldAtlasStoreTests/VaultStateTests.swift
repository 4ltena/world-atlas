import Foundation
import Testing
@testable import WorldAtlasStore

@Suite struct VaultStateTests {
    func tempVault() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("wa-state-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    @Test func writesThenReadsBack() throws {
        let v = try tempVault()
        VaultState.write(VaultState(openNode: "場所/職人街.md"), vault: v)
        #expect(VaultState.read(vault: v).openNode == "場所/職人街.md")
    }

    @Test func missingFileGivesTheDefault() throws {
        #expect(VaultState.read(vault: try tempVault()) == VaultState())
    }

    @Test func brokenFileGivesTheDefaultWithoutThrowing() throws {
        let v = try tempVault()
        let dir = v.appendingPathComponent(".atlas")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "これは JSON ではない".write(to: dir.appendingPathComponent("state.json"), atomically: true, encoding: .utf8)
        #expect(VaultState.read(vault: v) == VaultState())
    }

    @Test func keysAreEnglish() throws {
        let v = try tempVault()
        VaultState.write(VaultState(openNode: "場所/職人街.md"), vault: v)
        let text = try String(contentsOf: v.appendingPathComponent(".atlas/state.json"), encoding: .utf8)
        #expect(text.contains("\"openNode\""))
    }

    @Test func writingCreatesTheAtlasDirectory() throws {
        let v = try tempVault()
        VaultState.write(VaultState(openNode: nil), vault: v)
        #expect(FileManager.default.fileExists(atPath: v.appendingPathComponent(".atlas/state.json").path))
    }

    @Test func aVaultThatIsGoneIsNotBroughtBack() throws {
        // 窓を開いたまま vault を外へ移すことがある。中間ディレクトリごと作ると、
        // 消えた vault が state.json だけを持つ空のディレクトリとして生き返る。
        let v = try tempVault()
        try FileManager.default.removeItem(at: v)
        VaultState.write(VaultState(openNode: "場所/職人街.md"), vault: v)
        #expect(!FileManager.default.fileExists(atPath: v.path))
    }
}
