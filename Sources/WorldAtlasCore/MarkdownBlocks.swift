import Foundation

public enum MarkdownBlocks {
    public enum Block: Equatable, Sendable {
        case heading(level: Int, text: String)
        case list([String])
        case paragraph(String)
    }

    /// 空行で段に分け、段ごとに見出し、箇条書き、段落を判定する。
    /// コードフェンスや引用は扱わない（設計書 14 節）。
    public static func split(_ body: String) -> [Block] {
        let text = body.replacingOccurrences(of: "\r\n", with: "\n")
        var blocks: [Block] = []
        var buffer: [String] = []
        func flush() {
            guard !buffer.isEmpty else { return }
            let first = buffer[0]
            if buffer.count == 1, let h = heading(first) {
                blocks.append(h)
            } else if buffer.allSatisfy({ $0.hasPrefix("- ") }) {
                blocks.append(.list(buffer.map { String($0.dropFirst(2)) }))
            } else {
                blocks.append(.paragraph(buffer.joined(separator: "\n")))
            }
            buffer.removeAll()
        }
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(line)
            if s.trimmingCharacters(in: .whitespaces).isEmpty { flush() } else { buffer.append(s) }
        }
        flush()
        return blocks
    }

    private static func heading(_ line: String) -> Block? {
        var level = 0
        var rest = Substring(line)
        while rest.first == "#", level < 3 { level += 1; rest = rest.dropFirst() }
        guard level > 0, rest.first == " " else { return nil }
        return .heading(level: level, text: String(rest.dropFirst()))
    }
}
