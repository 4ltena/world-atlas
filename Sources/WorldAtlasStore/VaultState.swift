import Foundation

/// vault ごとに覚えておく値。`<vault>/.atlas/state.json` に置く。
/// 利用者が書く形式（世界.yaml と front matter）は日本語の鍵だが、これはアプリが
/// 書く内部の記録なので鍵は英語である（設計書 11 節）。
public struct VaultState: Codable, Equatable, Sendable {
    /// 開いている節点の、vault からの相対パス。
    public var openNode: String?
    public init(openNode: String? = nil) { self.openNode = openNode }

    static func url(vault: URL) -> URL {
        vault.appendingPathComponent(".atlas/state.json")
    }

    /// 読めない、壊れている、無い、のいずれでも既定へ戻す。ここで throw しない。
    public static func read(vault: URL) -> VaultState {
        guard let data = try? Data(contentsOf: url(vault: vault)),
              let s = try? JSONDecoder().decode(VaultState.self, from: data) else { return VaultState() }
        return s
    }

    /// 書けなければ黙って諦める。覚え書きが一つ残らないだけで、作業は続けられる。
    public static func write(_ state: VaultState, vault: URL) {
        // vault が消えていたら書かない。中間ディレクトリごと作る呼び出しは、外へ移された
        // vault を空のディレクトリとして復活させてしまう。
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: vault.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return }
        let f = url(vault: vault)
        try? FileManager.default.createDirectory(at: f.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: f, options: .atomic)
    }
}
