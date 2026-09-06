import AppKit
import SwiftUI

/// 二本指の横スワイプとマウスのホイールで年表を左右に動かす（設計書 8.6）。
///
/// SwiftUI に `scrollWheel` を受ける口が無い。`NSViewRepresentable` を重ねる手は使えない——
/// 当たり判定を持たせると下の掴みとピンチを塞ぎ、持たせないとスクロールも届かないためである。
/// **窓のイベントを覗いて、指が年表の矩形の中にあるときだけ受ける。**
/// 当たり判定に一切触らないので、既にある操作の振る舞いは変わらない。
struct ScrollPanReader: ViewModifier {
    /// 年表の矩形（窓の座標、左上が原点）。`geo.frame(in: .global)` の値を渡す。
    var frame: CGRect
    /// 横に動かす点数。正なら過去へ戻る。
    var onScroll: (Double) -> Void

    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                    handle(event)
                    return event    // 覗くだけ。イベントは止めない
                }
            }
            .onDisappear {
                if let m = monitor { NSEvent.removeMonitor(m) }
                monitor = nil
            }
    }

    private func handle(_ event: NSEvent) {
        // AppKit は左下が原点。SwiftUI の .global は左上が原点なので、y を折り返す。
        guard let content = event.window?.contentView else { return }
        let p = event.locationInWindow
        guard frame.contains(CGPoint(x: p.x, y: content.bounds.height - p.y)) else { return }

        // 横の回転を優先し、無ければ縦を横として使う。ホイールしか無い環境のため。
        let raw = event.scrollingDeltaX != 0 ? event.scrollingDeltaX : event.scrollingDeltaY
        guard raw != 0 else { return }
        // trackpad は点数で来る。ホイールは行数で来るので、点数へ均す。
        onScroll(Double(event.hasPreciseScrollingDeltas ? raw : raw * 10))
    }
}
