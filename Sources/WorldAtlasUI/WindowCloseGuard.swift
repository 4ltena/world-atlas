import AppKit
import SwiftUI

/// 窓を閉じる前に問いを挟む(設計書 8.3)。SwiftUI に閉じるのを止める口が無いので、
/// `NSWindow` の delegate を一枚かぶせる。**判断は `VaultStore` にあり、ここは尋ねて答えを返すだけ。**
struct WindowCloseGuard: NSViewRepresentable {
    var shouldClose: () -> Bool
    /// 関門を抜けた印。**真になったら、この橋が載っている窓を閉じる。**
    var wantsClose: Bool

    func makeCoordinator() -> Coordinator { Coordinator(shouldClose: shouldClose) }

    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        // 窓に載るのは次の走査の後なので、そこで delegate を差す。
        DispatchQueue.main.async { context.coordinator.attach(to: v.window) }
        return v
    }

    func updateNSView(_ v: NSView, context: Context) {
        context.coordinator.shouldClose = shouldClose
        context.coordinator.attach(to: v.window)
        // **`NSApplication.shared.keyWindow` を閉じない。**承認してから閉じるまでに
        // 前面の窓が変わっていることがあり、そのときは別の窓——未保存かもしれない窓——が
        // 閉じる。閉じてよいと言われたのは、この橋が載っているこの窓である。
        if wantsClose { context.coordinator.closeOwnWindow() }
    }

    @MainActor
    final class Coordinator: NSObject, NSWindowDelegate {
        var shouldClose: () -> Bool
        /// もとの delegate。SwiftUI が差しているものを壊さないよう、知らない問いは渡す。
        // `forwardingTarget(for:)` overrides a nonisolated NSObject method, so it can't
        // be @MainActor even though this class is. AppKit only ever calls it on the
        // main thread, so `nonisolated(unsafe)` here is safe in practice.
        nonisolated(unsafe) private weak var original: NSWindowDelegate?
        private weak var window: NSWindow?

        init(shouldClose: @escaping () -> Bool) { self.shouldClose = shouldClose }

        func attach(to window: NSWindow?) {
            guard let window, window !== self.window else { return }
            self.window = window
            if window.delegate !== self {
                original = window.delegate
                window.delegate = self
            }
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool { shouldClose() }

        /// 関門を抜けたので閉じる。`windowShouldClose` はもう一度呼ばれるが、
        /// そのときは未保存の編集が無いので通る。
        func closeOwnWindow() { window?.close() }

        override func responds(to aSelector: Selector!) -> Bool {
            super.responds(to: aSelector) || (original?.responds(to: aSelector) ?? false)
        }

        override func forwardingTarget(for aSelector: Selector!) -> Any? { original }
    }
}
