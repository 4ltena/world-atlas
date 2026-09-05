import CoreGraphics
import Foundation

/// 年表の縦の割り付け。y と行番号の相互の変換だけを持つ。
public struct TimelineLayout: Equatable, Sendable {
    /// 目盛りの帯の高さ。
    public static let tickHeight = 22.0
    /// これ以上は太らせない。行は与えられた高さを分け合い、この値で頭打ちになる。
    /// **labelThreshold より大きくしておくこと。**さもないと名札が出る高さに決して届かない。
    public static let maximumRowHeight = 36.0
    /// これ以上は縮めない。足りなければ縦に流す（設計書 14 節）。
    public static let minimumRowHeight = 10.0
    /// 行の高さがこれを超えると名札の列と帯の中の文字が現れる（設計書 8.6）。
    public static let labelThreshold = 24.0
    public static let rowGap = 2.0

    public var rowHeight: Double

    public var tickHeight: Double { Self.tickHeight }
    public var rowGap: Double { Self.rowGap }
    public var showsLabels: Bool { rowHeight > Self.labelThreshold }

    public func y(ofRow i: Int) -> Double {
        Self.tickHeight + Double(i) * (rowHeight + Self.rowGap)
    }

    public func row(atY y: Double) -> Int? {
        let inside = y - Self.tickHeight
        guard inside >= 0 else { return nil }
        let pitch = rowHeight + Self.rowGap
        let i = Int(inside / pitch)
        // 行と行のあいだの隙間は、どの行でもない。
        return inside - Double(i) * pitch <= rowHeight ? i : nil
    }

    /// 与えられた高さを rowCount 行で分け合う。上限で頭打ちにし、10 まで縮め、
    /// それでも足りなければ縦に流す（設計書 14 節）。
    /// **高さに応じて行が太ること自体が要件である**——設計書 8.6 の名札は
    /// 「境目を掴んで行の高さが 24 を超えると」出るので、固定の高さでは条件に届かない。
    public static func fitting(rowCount: Int, height: Double) -> (layout: TimelineLayout, scrolls: Bool) {
        guard rowCount > 0 else { return (TimelineLayout(rowHeight: maximumRowHeight), false) }
        let available = max(height - tickHeight, 0)
        let share = available / Double(rowCount) - rowGap
        if share < minimumRowHeight { return (TimelineLayout(rowHeight: minimumRowHeight), true) }
        return (TimelineLayout(rowHeight: min(share, maximumRowHeight)), false)
    }
}

/// 押した位置が何であるかを決める。逆変換なので目で確かめにくく、ここを試験できる形にしておく。
public enum TimelineHit {
    public enum Target: Equatable, Sendable {
        /// 目盛りの帯。押した位置の年。年カーソルをそこへ飛ばす。
        case ticks(Double)
        /// 年カーソルの線そのもの。掴んで動かす。
        case cursor
        /// 出来事の菱形。節点の path と年。
        case mark(String, Int)
        /// 改称の菱形。
        case rename(String, Int)
        /// 帯そのもの。
        case row(String)
    }

    /// 掴める幅。菱形と線は細いので、指の届く範囲を広げる。
    static let grab = 6.0

    /// `worldEnd` は世界の右端（`Extent.hi`）。**`to` が nil の帯はそこで終わる。**
    /// 年カーソルはその 10 年先まで動けるが、帯は伸びない（設計書 6 節）。描画（課題 11）と
    /// 同じ終端を使わないと、何も描かれていない場所に板が出る。
    public static func target(at p: CGPoint, rows: [TimelineRow], layout: TimelineLayout,
                              transform t: TimelineTransform, year: Int, worldEnd: Int) -> Target? {
        // 年カーソルはいちばん上にある。帯より先に判定する。
        if abs(p.x - t.x(of: Double(year))) <= grab, p.y >= layout.tickHeight { return .cursor }
        if p.y < layout.tickHeight { return .ticks(t.year(atX: p.x)) }
        guard let i = layout.row(atY: p.y), i < rows.count else { return nil }
        let r = rows[i]
        // 菱形は帯の上に乗っているので、帯より先に判定する。
        // **改称を先に見る。**描くのは出来事 → 改称の順で、後に描いた改称が上に乗るためである。
        // 同じ年に両方あるとき（見本の vault のエルデン邑 318 年）、見えているのは改称である。
        for a in r.renames where abs(p.x - t.x(of: Double(a.from))) <= grab { return .rename(r.path, a.from) }
        for m in r.marks where abs(p.x - t.x(of: Double(m.year))) <= grab { return .mark(r.path, m.year) }
        let x = t.year(atX: p.x)
        if r.isPoint {
            return abs(p.x - t.x(of: Double(r.from))) <= grab ? .row(r.path) : nil
        }
        let end = Double(r.to ?? worldEnd)
        return x >= Double(r.from) && x <= end ? .row(r.path) : nil
    }
}
