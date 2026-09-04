import Foundation
import GRDB

/// 索引のデータベース。表の定義はここ一箇所に持つ。
/// 索引は真実ではなく、いつ消しても vault の走査で作り直せる（設計書 5 節）。
public enum IndexDatabase {

    /// 一度出した版は書き換えない。育てるときは次の版を足す。
    public static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1_index") { db in
            // 主キーは path。保存名は一意にしない（同名の二ファイルを両方残すため）。
            // broken と mismatch はファイル単位で決まるので持つ。重複は持たない。
            try db.create(table: "node") { t in
                t.column("path", .text).primaryKey().notNull()
                t.column("name", .text).notNull()
                t.column("kind", .text).notNull()
                t.column("category", .text).notNull()
                t.column("from", .integer).notNull()
                t.column("to", .integer)
                t.column("isPoint", .boolean).notNull()
                t.column("parent", .text)
                t.column("mtime", .double).notNull()
                t.column("broken", .boolean).notNull()
                t.column("mismatch", .boolean).notNull()
            }
            try db.create(index: "idx_node_name", on: "node", columns: ["name"])
            // 子表の node 列は path を指す。
            try db.create(table: "alias") { t in
                t.column("node", .text).notNull()
                t.column("from", .integer).notNull()
                t.column("name", .text).notNull()
            }
            try db.create(index: "idx_alias_name", on: "alias", columns: ["name"])
            try db.create(table: "mark") { t in
                t.column("node", .text).notNull()
                t.column("year", .integer).notNull()
                t.column("label", .text).notNull()
            }
            try db.create(table: "rule") { t in
                t.column("node", .text).notNull()
                t.column("from", .integer).notNull()
                t.column("to", .integer)
                t.column("polity", .text).notNull()
            }
            try db.create(table: "lineage") { t in
                t.column("node", .text).notNull()
                t.column("year", .integer).notNull()
                t.column("kind", .text).notNull()
                t.column("origin", .text).notNull()
            }
            // target は本文の生の文字列。保存名への解決は snapshot を作るときに行う。
            try db.create(table: "ref") { t in
                t.column("source", .text).notNull()
                t.column("target", .text).notNull()
                t.column("count", .integer).notNull()
            }
            try db.create(index: "idx_ref_target", on: "ref", columns: ["target"])
            try db.create(table: "calendar") { t in
                t.column("name", .text).primaryKey().notNull()
                t.column("offset", .integer).notNull()
            }
        }
        return m
    }

    /// `<vault>/.atlas/index.sqlite` を開く。開けなければ消して作り直す。
    public static func open(vault: URL) throws -> DatabaseQueue {
        let dir = vault.appendingPathComponent(".atlas", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("index.sqlite")
        do {
            return try openAndMigrate(file)
        } catch {
            try? FileManager.default.removeItem(at: file)
            for suffix in ["-wal", "-shm"] {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent("index.sqlite" + suffix))
            }
            return try openAndMigrate(file)
        }
    }

    private static func openAndMigrate(_ file: URL) throws -> DatabaseQueue {
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA synchronous = NORMAL")
        }
        let queue = try DatabaseQueue(path: file.path, configuration: configuration)
        try migrator.migrate(queue)
        return queue
    }
}
