import Foundation
import WorldAtlasCore
import WorldAtlasStore

/// 描き終えた本文の一段。箇条書きだけ lines が二つ以上になる。
public struct RenderedBlock: Equatable, Identifiable, Sendable {
    public enum Style: Equatable, Sendable {
        case heading(Int)
        case bullet
        case paragraph
    }
    public var id: Int
    public var style: Style
    public var lines: [AttributedString]
}

public enum BodyRenderer {
    /// 本文を段に分け、`[[…]]` を解決してリンクにした AttributedString にする。
    /// 扱うのは見出し、箇条書き、段落と、インラインの装飾だけである（設計書 14 節）。
    public static func render(_ body: String, snapshot: Snapshot, year: Int) -> [RenderedBlock] {
        MarkdownBlocks.split(body).enumerated().map { i, b in
            switch b {
            case let .heading(level, text):
                return RenderedBlock(id: i, style: .heading(level), lines: [inline(text, snapshot, year)])
            case let .list(items):
                return RenderedBlock(id: i, style: .bullet, lines: items.map { inline($0, snapshot, year) })
            case let .paragraph(text):
                return RenderedBlock(id: i, style: .paragraph, lines: [inline(text, snapshot, year)])
            }
        }
    }

    /// `[[…]]` を Markdown のリンクに書き換えてから一度だけ解析する。
    /// 解析器に渡す文字列を組み立てるので、リンクの文字だけは角括弧と円記号を逃がす。
    /// 残りの文字はそのまま渡し、太字などのインライン装飾を効かせる。
    static func inline(_ text: String, _ s: Snapshot, _ year: Int) -> AttributedString {
        var md = ""
        var i = text.startIndex
        while let open = text.range(of: "[[", range: i..<text.endIndex),
              let close = text.range(of: "]]", range: open.upperBound..<text.endIndex) {
            md += String(text[i..<open.lowerBound])
            let raw = String(text[open.upperBound..<close.lowerBound])
            if let path = s.path(ofName: raw), let n = s.nodes[path] {
                md += "[\(escaped(n.displayName(at: year)))](\(NodeURL.make(path: path).absoluteString))"
            } else {
                // 解決できないものは文字のまま出す。角括弧を逃がして、参照の記法として
                // 読まれないようにする。
                md += "\\[\\[\(escaped(raw))\\]\\]"
            }
            i = close.upperBound
        }
        md += String(text[i...])
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: md, options: opts)) ?? AttributedString(text)
    }

    private static func escaped(_ s: String) -> String {
        var out = ""
        for ch in s {
            if ch == "\\" || ch == "[" || ch == "]" { out.append("\\") }
            out.append(ch)
        }
        return out
    }
}
