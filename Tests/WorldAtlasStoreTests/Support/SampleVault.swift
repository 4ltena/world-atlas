import Foundation

enum SampleVault {
    /// リポジトリ内の Samples/灰海。テストファイルの場所から遡る。
    static var url: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Support
            .deletingLastPathComponent() // WorldAtlasStoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // リポジトリ
            .appendingPathComponent("Samples/灰海", isDirectory: true)
    }

    /// 書き換えるテストのために一時ディレクトリへ複製する。.atlas は複製しない。
    static func copy() throws -> URL {
        let dst = FileManager.default.temporaryDirectory.appendingPathComponent("haikai-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: url, to: dst)
        try? FileManager.default.removeItem(at: dst.appendingPathComponent(".atlas"))
        return dst
    }
}
