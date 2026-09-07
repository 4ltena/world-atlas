import Foundation
import WorldAtlasCore

/// ⌘N が作る節点のファイル(設計書 8.3)。`名前`、`種別`、期間だけを持つ。
public enum NodeCreator {
    public struct Failure: Error, Equatable, Sendable {
        public var message: String
        public init(message: String) { self.message = message }
    }

    /// 作って、vault からの相対パスを返す。
    /// **種別には型の名前を入れる。**空にすると `FrontMatter.parse` が
    /// 「種別 がありません」で弾き、必ず壊れた節点になる。
    public static func create(in vault: URL, kind: Kind, name: String, year: Int) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw Failure(message: "名前を入れてください。")
        }
        // ディレクトリの外へ出る名前と、隠しファイルになる名前を断る。
        guard !trimmed.contains("/"), !trimmed.hasPrefix("."), trimmed != ".." else {
            throw Failure(message: "名前に / は使えません。. で始めることもできません。")
        }
        let dir = vault.appendingPathComponent(kind.rawValue)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(trimmed).md")
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw Failure(message: "同じ名前のファイルが既にあります。別の名前にしてください。")
        }
        // 型ごとに期間の鍵が違う。ここを間違えると必ず壊れた節点になる(設計書 4.3)。
        let period: String
        switch kind {
        case .event: period = "年: \(year)"
        case .law: period = "効力: [\(year), 現在]"
        default: period = "期間: [\(year), 現在]"
        }
        // **名前を素で埋め込まない。**`#見本` は行がコメントになって 名前 が消え、
        // `港: 北` は鍵が二つあるように見えて不正な YAML になる。
        // 引用の判断は WorldFile.scalar が既に持っている(Yams に任せる形)。
        let body = """
        ---
        名前: \(WorldFile.scalar(trimmed))
        種別: \(kind.rawValue)
        \(period)
        ---

        """
        try body.write(to: url, atomically: true, encoding: .utf8)
        return "\(kind.rawValue)/\(trimmed).md"
    }
}
