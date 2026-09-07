import Foundation
import CoreServices

/// FSEvents で vault を再帰的に見張り、変わったファイルを束ねて知らせる。
public final class VaultWatcher: @unchecked Sendable {
    private let vault: URL
    /// シンボリックリンク解決済みの vault パス。Foundation の resolvingSymlinksInPath は
    /// /var 等を互換のためわざと解決しないので、realpath(3) を直に使う。FSEvents に渡す
    /// 監視の根と、届くイベントのパスをこれで揃える。判定にのみ使い、onChange へ渡す URL の
    /// 組み立てには使わない（下記 mapToVaultNamespace を参照）。
    private let resolvedVault: String
    private let latency: TimeInterval
    private let onChange: @Sendable ([URL]) -> Void
    private let queue = DispatchQueue(label: "world-atlas.watcher")
    private var stream: FSEventStreamRef?

    public init(vault: URL, latency: TimeInterval = 0.3, onChange: @escaping @Sendable ([URL]) -> Void) {
        self.vault = vault
        self.resolvedVault = VaultWatcher.realPath(vault)
        self.latency = latency
        self.onChange = onChange
    }

    private static func realPath(_ url: URL) -> String {
        var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
        return buf.withUnsafeMutableBufferPointer { p -> String in
            guard let base = p.baseAddress, realpath(url.path, base) != nil else { return url.standardizedFileURL.path }
            return String(cString: base)
        }
    }

    /// FSEvents が返した実体パス一本を判定する。.atlas そのものとその下、vault の根そのもの
    /// （ディレクトリ作成直後などに親の mtime が動いて届くことがある）は対象外として nil を
    /// 返す。対象なら、実体パスの vault 部分を元の vault（呼び出し側が渡した、まだ解決して
    /// いない URL）に差し替えて返す。実体パスをそのまま onChange へ渡すと、Indexer 側の
    /// vault.standardizedFileURL との比較が「そのパスが今も存在するか」で結果の変わる
    /// Foundation の挙動に左右されてしまう（存在しない＝消えたファイルの時だけ食い違う）ため、
    /// ここで vault の名前空間に一度戻しておく。存在するかどうかはこの関数では見ない。
    static func mapToVaultNamespace(resolvedVault: String, vault: URL, rawPath: String) -> URL? {
        guard rawPath != resolvedVault else { return nil }
        let atlas = resolvedVault + "/.atlas"
        guard rawPath != atlas, !rawPath.hasPrefix(atlas + "/") else { return nil }
        guard rawPath.hasPrefix(resolvedVault + "/") else { return nil }
        let remainder = String(rawPath.dropFirst(resolvedVault.count + 1))
        return vault.appendingPathComponent(remainder)
    }

    public func start() throws {
        guard stream == nil else { return }
        // **流れに自分を強く持たせる。**passUnretained だと、解放が始まったあとに、
        // 既にキューへ積まれていたコールバックが `takeUnretainedValue()` で自分を掴み直す。
        // 参照数が解放中に戻るので `deallocated with non-zero retain count` で落ちる——
        // 並行して走る試験で実際に abort を観測した（Indexer の破棄 → VaultWatcher の
        // deinit → swift_deallocClassInstance の致命エラー）。窓を閉じる経路も同じである。
        // +1 は `stop()` の `FSEventStreamRelease` が解いて release で戻す。
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passRetained(self).toOpaque(),
            retain: nil,
            release: { Unmanaged<VaultWatcher>.fromOpaque($0!).release() },
            copyDescription: nil)
        let paths = [resolvedVault] as CFArray
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        guard let s = FSEventStreamCreate(nil, VaultWatcher.callback, &context, paths, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags) else {
            throw IndexerError(message: "監視を始められない: \(vault.path)")
        }
        FSEventStreamSetDispatchQueue(s, queue)
        guard FSEventStreamStart(s) else {
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
            throw IndexerError(message: "監視を開始できない: \(vault.path)")
        }
        stream = s
    }

    public func stop() {
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
    }

    deinit { stop() }

    private static let callback: FSEventStreamCallback = { _, info, count, eventPaths, _, _ in
        guard let info else { return }
        let me = Unmanaged<VaultWatcher>.fromOpaque(info).takeUnretainedValue()
        guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }
        let urls = paths.compactMap { VaultWatcher.mapToVaultNamespace(resolvedVault: me.resolvedVault, vault: me.vault, rawPath: $0) }
        let unique = Array(Set(urls)).sorted { $0.path < $1.path }
        if !unique.isEmpty { me.onChange(unique) }
    }
}
