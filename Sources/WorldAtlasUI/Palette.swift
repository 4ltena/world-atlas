import AppKit
import SwiftUI

/// 設計書 10 節。
public enum Palette {
    /// 朱。年カーソル、自身の行、リンク、選択している行の左端の帯に使う。
    public static let accent = Color(light: NSColor(srgbRed: 0.71, green: 0.20, blue: 0.16, alpha: 1),
                                     dark: NSColor(srgbRed: 0.88, green: 0.44, blue: 0.37, alpha: 1))
    /// 印を出す橙。
    public static let warning = Color(light: NSColor(srgbRed: 0.72, green: 0.44, blue: 0.06, alpha: 1),
                                      dark: NSColor(srgbRed: 0.90, green: 0.62, blue: 0.24, alpha: 1))

    // MARK: 面。線を引かず、この三段の濃淡で分ける（設計書 10 節）。

    /// 原稿の地。
    public static let ground = Color(light: NSColor(srgbRed: 0.984, green: 0.976, blue: 0.965, alpha: 1),
                                     dark: NSColor(srgbRed: 0.110, green: 0.102, blue: 0.098, alpha: 1))
    /// sidebar の地。原稿より一段暗い。
    public static let sidebar = Color(light: NSColor(srgbRed: 0.949, green: 0.933, blue: 0.910, alpha: 1),
                                      dark: NSColor(srgbRed: 0.090, green: 0.082, blue: 0.078, alpha: 1))
    /// 選択と hover の霞。
    public static let veil = Color(light: NSColor(srgbRed: 0.918, green: 0.894, blue: 0.863, alpha: 1),
                                   dark: NSColor(srgbRed: 0.165, green: 0.153, blue: 0.145, alpha: 1))
    /// 役割の違う帯を分ける一本だけに使う罫。
    public static let rule = Color(light: NSColor(srgbRed: 0.878, green: 0.847, blue: 0.816, alpha: 1),
                                   dark: NSColor(srgbRed: 0.180, green: 0.165, blue: 0.157, alpha: 1))

    // MARK: 勢力の色と模様。

    public static let polityCount = 5

    /// 勢力の色。2026-09-05 に dataviz の検証器を新しい地に対して --pairs all で通した値。
    /// 目で選び直さないこと。変えるなら検証器を回し直す。
    private static let polityColors: [Color] = [
        Color(light: NSColor(srgbRed: 0.612, green: 0.012, blue: 0.318, alpha: 1),   // #9c0351
              dark: NSColor(srgbRed: 0.824, green: 0.192, blue: 0.427, alpha: 1)),   // #d2316d
        Color(light: NSColor(srgbRed: 0.773, green: 0.510, blue: 0.051, alpha: 1),   // #c5820d
              dark: NSColor(srgbRed: 0.757, green: 0.522, blue: 0.051, alpha: 1)),   // #c1850d
        Color(light: NSColor(srgbRed: 0.024, green: 0.498, blue: 0.102, alpha: 1),   // #067f1a
              dark: NSColor(srgbRed: 0.031, green: 0.522, blue: 0.208, alpha: 1)),   // #088535
        Color(light: NSColor(srgbRed: 0.090, green: 0.733, blue: 0.855, alpha: 1),   // #17bbda
              dark: NSColor(srgbRed: 0.055, green: 0.584, blue: 0.706, alpha: 1)),   // #0e95b4
        Color(light: NSColor(srgbRed: 0.486, green: 0.376, blue: 0.922, alpha: 1),   // #7c60eb
              dark: NSColor(srgbRed: 0.420, green: 0.251, blue: 0.788, alpha: 1)),   // #6b40c9
    ]

    /// 色だけに頼らないための二本目の手がかり。CVD の分離が 6〜8 の帯にあるので、
    /// 模様が無いと色覚によっては見分けられない（設計書 10 節）。
    /// **本数を色の数と違えてあるのは、両方が同じ周期だと六つ目で色も模様も 0 番と重なるためである。**
    /// 5 と 4 は互いに素なので、組が重なるのは 20 個目からになる。
    private static let polityDashes: [[CGFloat]] = [
        [],           // 実線
        [6, 3],
        [2, 2],
        [10, 3, 2, 3],
    ]

    public static let polityDashCount = 4

    public static func polity(_ index: Int) -> Color { polityColors[wrap(index, polityCount)] }
    public static func polityDash(_ index: Int) -> [CGFloat] { polityDashes[wrap(index, polityDashCount)] }

    /// 勢力が六つ以上でも落ちない。色と模様は別の周期で巡回する。
    private static func wrap(_ i: Int, _ n: Int) -> Int { ((i % n) + n) % n }
}

extension Color {
    /// 明るい地と暗い地で別の色を返す。色は先に作っておき、閉包の中では選ぶだけにする。
    init(light: NSColor, dark: NSColor) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}
