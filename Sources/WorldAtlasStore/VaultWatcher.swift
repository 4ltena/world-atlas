import Foundation
import CoreServices

/// FSEvents で vault を再帰的に見張り、変わったファイルを束ねて知らせる。
public final class VaultWatcher: @unchecked Sendable {
    private let vault: URL
    /// シンボリックリンク解決済みの vault パス。Foundation の resolvingSymlinksInPath は
    /// /var 等を互換のためわざと解決しないので、realpath(3) を直に使う。FSEvents は、監視の
    /// 根に渡した文字列そのものと一致する時だけそれを素通しで返し、それ以外はカーネルの
    /// 実体パス（/private/var/… 等）で返す。根に解決済みパスを渡しておけば、この二通りが
    /// 揃う。
    private let resolvedVault: String
    private let atlasPath: String
    private let latency: TimeInterval
    private let onChange: @Sendable ([URL]) -> Void
    private let queue = DispatchQueue(label: "world-atlas.watcher")
    private var stream: FSEventStreamRef?

    public init(vault: URL, latency: TimeInterval = 0.3, onChange: @escaping @Sendable ([URL]) -> Void) {
        self.vault = vault
        self.resolvedVault = VaultWatcher.realPath(vault)
        self.atlasPath = resolvedVault + "/.atlas"
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

    public func start() throws {
        guard stream == nil else { return }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let paths = [resolvedVault] as CFArray
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        guard let s = FSEventStreamCreate(nil, VaultWatcher.callback, &context, paths, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags) else {
            throw IndexerError(message: "監視を始められない: \(vault.path)")
        }
        FSEventStreamSetDispatchQueue(s, queue)
        FSEventStreamStart(s)
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
        // FSEvents が返す文字列そのものが、すでにカーネルの実体パスであり正準な形。ここへ
        // URL.standardizedFileURL を重ねると、存在するパスだけ /private が剥がれて存在しない
        // パス（rename 前の一時ファイル等）は剥がれず、比較の左右がずれる。そのため素の文字列
        // のまま .atlas と比べる。
        let atlas = me.atlasPath
        // ディレクトリの中に初めて何かができた直後、FSEvents は個々のファイルに加えて
        // vault の根そのものも「変わった」と報告することがある（親ディレクトリの mtime が
        // 動くため）。根そのものはファイルではなく、報告すべき対象を持たないので落とす。
        let urls = paths
            .filter { $0 != atlas && !$0.hasPrefix(atlas + "/") && $0 != me.resolvedVault }
            .map { URL(fileURLWithPath: $0) }
        let unique = Array(Set(urls)).sorted { $0.path < $1.path }
        if !unique.isEmpty { me.onChange(unique) }
    }
}
