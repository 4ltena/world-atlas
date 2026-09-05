import Foundation

/// 本文中のリンクが指す先。押されたときに課題 12 の OpenURLAction が読み取る。
/// 相対パスは区切りの / も含めて丸ごと一区画に入れる。
public enum NodeURL {
    static let scheme = "worldatlas"
    static let host = "node"

    /// 符号化から外す文字。/ は区画が割れないように、( ) は Markdown のリンクの
    /// 目的地として書いたときに括弧の対応で読み違えられないように、いずれも符号化する。
    private static let allowed: CharacterSet = {
        var cs = CharacterSet.urlPathAllowed
        cs.subtract(CharacterSet(charactersIn: "/()"))
        return cs
    }()

    public static func make(path: String) -> URL {
        // Indexer が渡す path は、標準化した URL の path から作るため、macOS の一時
        // ディレクトリ（/var → /private/var のようなシンボリックリンク解決）を経由すると
        // 濁点付きの仮名などが分解形（NFD）になることがある。Swift の文字列比較は
        // 正準等価で見分けが付かないが、百分率符号化は素の UTF-8 バイト列を見るため、
        // ここで結合形（NFC）へそろえてから符号化し、同じ節点なら常に同じ URL にする。
        let normalized = path.precomposedStringWithCanonicalMapping
        let encoded = normalized.addingPercentEncoding(withAllowedCharacters: allowed) ?? normalized
        // 符号化した後の文字はすべて URL に使える文字なので、この組み立ては失敗しない。
        return URL(string: "\(scheme)://\(host)/\(encoded)")!
    }

    public static func path(from url: URL) -> String? {
        guard url.scheme == scheme, url.host() == host else { return nil }
        let p = url.path(percentEncoded: false)
        guard p.hasPrefix("/") else { return nil }
        return String(p.dropFirst())
    }
}
