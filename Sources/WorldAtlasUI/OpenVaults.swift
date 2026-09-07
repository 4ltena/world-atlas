import AppKit

/// 開いている vault の窓を弱く覚えておく。**⌘Q の関門がここを見る。**
///
/// **窓ごとの `windowShouldClose(_:)` は ⌘Q では呼ばれない。**終了のとき窓は `close()` で
/// 閉じられ、`close()` は問い合わせを送らない。だから終了の関門は別に要る(設計書 8.3)。
@MainActor
public enum OpenVaults {
    /// 窓を強く持たない。**持つと、閉じた窓が終了を止め続ける。**
    private final class Entry {
        weak var store: VaultStore?
        weak var window: NSWindow?
        init(_ s: VaultStore, _ w: NSWindow?) { store = s; window = w }
    }
    private static var entries: [Entry] = []

    public static func register(_ store: VaultStore, window: NSWindow?) {
        entries.removeAll { $0.store == nil || $0.store === store }
        entries.append(Entry(store, window))
    }

    public static func forget(_ store: VaultStore) {
        entries.removeAll { $0.store == nil || $0.store === store }
    }

    /// 未保存を抱えている最初の窓。
    public static var firstDirty: (store: VaultStore, window: NSWindow?)? {
        for e in entries {
            guard let s = e.store else { continue }
            if s.canSave { return (s, e.window) }   // 移動・窓閉じと同じ述語
        }
        return nil
    }

    /// 終了してよいか。**駄目なら、その窓を前に出して三択を出す。**
    /// 二つ以上が未保存でも、一度に出す問いは一つである。答えてもう一度 ⌘Q を押すと次が出る。
    @discardableResult
    public static func mayQuit() -> Bool {
        guard let (store, window) = firstDirty else { return true }
        window?.makeKeyAndOrderFront(nil)
        _ = store.requestClose()      // 三択を出す
        return false
    }

    /// 試験のあいだ、前の試験が残した帳面を持ち越さないため。
    static func forgetAllForTest() { entries.removeAll() }
}
