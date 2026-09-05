import Foundation
import WorldAtlasStore

enum TestVault {
    /// リポジトリ内の Samples/灰海 を一時ディレクトリへ複製する。.atlas は複製しない。
    static func copiedSample() throws -> URL {
        let src = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Support
            .deletingLastPathComponent() // WorldAtlasUITests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // リポジトリ
            .appendingPathComponent("Samples/灰海", isDirectory: true)
        let dst = FileManager.default.temporaryDirectory.appendingPathComponent("wa-ui-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: src, to: dst)
        try? FileManager.default.removeItem(at: dst.appendingPathComponent(".atlas"))
        return dst
    }

    /// 見本の vault を索引した本物の snapshot。
    static func sample() async throws -> Snapshot {
        try await Indexer(vault: try copiedSample()).rebuild()
    }

    /// 与えた Markdown だけを持つ vault を作って索引する。鍵は "場所/A.md" の形。
    static func snapshot(_ files: [String: String], current: Int = 500) async throws -> Snapshot {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wa-ui-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try """
        名前: 試し
        基準暦: 帝国暦
        暦:
          - [帝国暦, 0]
        現在: \(current)

        """.write(to: dir.appendingPathComponent("世界.yaml"), atomically: true, encoding: .utf8)
        for (rel, text) in files {
            let f = dir.appendingPathComponent(rel)
            try FileManager.default.createDirectory(at: f.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: f, atomically: true, encoding: .utf8)
        }
        return try await Indexer(vault: dir).rebuild()
    }
}
