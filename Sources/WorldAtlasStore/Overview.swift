import Foundation
import WorldAtlasCore

/// `.atlas/overview/<年>.md` の中身（設計書 9 節）。
public struct OverviewDoc: Equatable, Sendable {
    public var model: String
    /// 生成に使った入力の要約値。今の材料から取り直した値と違えば「古い」。
    public var digest: String
    /// 生成時刻。**文字列のまま持つ。**画面には出さないので、解釈する理由が無い。
    public var generated: String
    public var text: String
}

/// 総観の五状態（設計書 8.4）。
public enum OverviewState: Equatable, Sendable {
    /// 未生成。**`none` と名づけない**——`Optional.none` と紛れて、
    /// `OverviewState?` を扱う場所で警告が出る（警告 0 が守れなくなる）。
    case missing
    /// Stage 6 が立てる。この段では起きない。
    case generating
    case ready(OverviewDoc)
    case stale(OverviewDoc)
    case noMaterial
}

public enum OverviewStore {
    public static func directory(vault: URL) -> URL {
        vault.appendingPathComponent(".atlas/overview", isDirectory: true)
    }

    static func fileURL(vault: URL, year: Int) -> URL {
        directory(vault: vault).appendingPathComponent("\(year).md")
    }

    /// 読めなければ nil。**ここで throw しない**——総観が読めないだけで窓が
    /// 立たなくなる理由が無い（`VaultState.read` と同じ構え）。
    public static func read(vault: URL, year: Int) -> OverviewDoc? {
        guard let raw = try? String(contentsOf: fileURL(vault: vault, year: year), encoding: .utf8)
        else { return nil }
        return parse(raw)
    }

    /// front matter と本文に割る。鍵は英語である（設計書 9 節）。
    /// **Yams を通さない。**三つの文字列を取るだけで、`WorldAtlasStore` に
    /// YAML の解析を持ち込む理由が無い。
    static func parse(_ raw: String) -> OverviewDoc? {
        var lines = raw.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return nil }
        lines.removeFirst()
        guard let end = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" })
        else { return nil }
        var fields: [String: String] = [:]
        for line in lines[..<end] {
            guard let c = line.firstIndex(of: ":") else { continue }
            let k = line[..<c].trimmingCharacters(in: .whitespaces)
            let v = line[line.index(after: c)...].trimmingCharacters(in: .whitespaces)
            fields[k] = v
        }
        guard let digest = fields["digest"] else { return nil }
        let body = lines[(end + 1)...].joined(separator: "\n")
        return OverviewDoc(model: fields["model"] ?? "",
                           digest: digest,
                           generated: fields["generated"] ?? "",
                           // 末尾の改行だけ落とす。段落の間の空行は本文の一部である。
                           text: body.hasSuffix("\n") ? String(body.dropLast()) : body)
    }

    /// 画面が出す状態を決める。`digest` は今の材料から取り直した値、
    /// `hasMaterial` は前後 12 年に出来事が一つでもあるか（設計書 9 節）。
    public static func state(vault: URL, year: Int, digest: String, hasMaterial: Bool) -> OverviewState {
        // **材料なしが先。**材料が消えた年に古い文が残っていることはある。
        // そのとき「古い」と出すと、Stage 6 の待ち行列が生成できない年を掴み続ける。
        guard hasMaterial else { return .noMaterial }
        guard let doc = read(vault: vault, year: year) else { return .missing }
        return doc.digest == digest ? .ready(doc) : .stale(doc)
    }
}
