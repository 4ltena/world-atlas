import AppKit
import SwiftUI

/// 設計書 10 節。勢力の五色はStage 3 の年表で足す。
public enum Palette {
    /// 朱。年カーソル、自身の行、リンクに使う。地の明暗で切り替える。
    public static let accent = Color(light: NSColor(srgbRed: 0.71, green: 0.20, blue: 0.16, alpha: 1),
                                     dark: NSColor(srgbRed: 0.88, green: 0.44, blue: 0.37, alpha: 1))
    /// 印を出す橙。
    public static let warning = Color(light: NSColor(srgbRed: 0.72, green: 0.44, blue: 0.06, alpha: 1),
                                      dark: NSColor(srgbRed: 0.90, green: 0.62, blue: 0.24, alpha: 1))
}

extension Color {
    /// 明るい地と暗い地で別の色を返す。色は先に作っておき、閉包の中では選ぶだけにする。
    init(light: NSColor, dark: NSColor) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}
