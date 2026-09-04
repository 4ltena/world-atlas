import Foundation
import Testing
import GRDB
@testable import WorldAtlasStore

@Suite struct IndexDatabaseTests {
    func tempVault() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wa-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func createsTablesUnderDotAtlas() throws {
        let vault = try tempVault()
        let q = try IndexDatabase.open(vault: vault)
        let tables: [String] = try q.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'grdb_%' AND name NOT LIKE 'sqlite_%' ORDER BY name")
        }
        #expect(tables == ["alias", "calendar", "lineage", "mark", "node", "ref", "rule"])
        #expect(FileManager.default.fileExists(atPath: vault.appendingPathComponent(".atlas/index.sqlite").path))
    }

    @Test func corruptFileIsReplaced() throws {
        let vault = try tempVault()
        let dir = vault.appendingPathComponent(".atlas")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not a database".utf8).write(to: dir.appendingPathComponent("index.sqlite"))
        let q = try IndexDatabase.open(vault: vault)
        let n = try q.read { db in try Int.fetchOne(db, sql: "SELECT count(*) FROM node") }
        #expect(n == 0)
    }
}
