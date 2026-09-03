import Foundation

public enum FrontMatter {
    public struct Split: Equatable, Sendable {
        public var yaml: String
        public var body: String
        /// 本文の最初の行のファイル内行番号（1 始まり）。
        public var bodyLine: Int
    }

    /// 先頭の `---` から次の `---` までを YAML として切り出す。改行は LF に揃える。
    public static func split(_ text: String) -> Split? {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first == "---" else { return nil }
        guard let close = lines.dropFirst().firstIndex(of: "---") else { return nil }
        let yaml = lines[1..<close].map(String.init).joined(separator: "\n")
        let bodyLines = lines[(close + 1)...]
        let body = bodyLines.map(String.init).joined(separator: "\n")
        return Split(
            yaml: yaml.isEmpty ? "" : yaml + "\n",
            body: body,
            bodyLine: close + 2
        )
    }
}
