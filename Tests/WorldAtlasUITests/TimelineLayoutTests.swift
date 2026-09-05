import Foundation
import Testing
import WorldAtlasCore
@testable import WorldAtlasUI

@Suite struct TimelineLayoutTests {
    let world = Extent(lo: 1, hi: 712)

    private func sampleRows() -> [TimelineRow] {
        // 250 年には出来事と改称が両方ある。見本の vault のエルデン邑（318 年）と同じ形である。
        [TimelineRow(path: "a", name: "甲", category: "区", from: 100, to: 300, isPoint: false, isRoot: true,
                     marks: [Mark(year: 200, label: "出来事"), Mark(year: 250, label: "同じ年の出来事")],
                     renames: [Alias(from: 250, name: "乙")],
                     rules: [], lineages: []),
         TimelineRow(path: "b", name: "丙", category: "宿", from: 150, to: nil, isPoint: false, isRoot: false,
                     marks: [], renames: [], rules: [], lineages: []),
         TimelineRow(path: "c", name: "丁", category: "事", from: 400, to: nil, isPoint: true, isRoot: false,
                     marks: [], renames: [], rules: [], lineages: [])]
    }

    // MARK: 割り付け

    @Test func roomyHeightGrowsTheRowsUpToTheCap() {
        // 行は与えられた高さを分け合う。上限まで伸びるから、境目を下げると名札が出る。
        let (l, scrolls) = TimelineLayout.fitting(rowCount: 3, height: 300)
        #expect(l.rowHeight == TimelineLayout.maximumRowHeight)
        #expect(!scrolls)
    }

    @Test func tightHeightShrinksTheRows() {
        let (l, scrolls) = TimelineLayout.fitting(rowCount: 12, height: 180)
        #expect(l.rowHeight < TimelineLayout.maximumRowHeight)
        #expect(l.rowHeight >= TimelineLayout.minimumRowHeight)
        #expect(!scrolls)
    }

    @Test func theSameRowsGetTallerWhenTheBoundaryIsDraggedDown() {
        // 設計書 8.6 の名札は「境目を掴んで行の高さが 24 を超えると」出る。
        // 高さが増えても行が太らないなら、その条件には決して届かない。
        let short = TimelineLayout.fitting(rowCount: 8, height: 180).layout
        let tall = TimelineLayout.fitting(rowCount: 8, height: 400).layout
        #expect(tall.rowHeight > short.rowHeight)
        #expect(!short.showsLabels)
        #expect(tall.showsLabels)
    }

    @Test func tooManyRowsScrollRatherThanShrinkBelowTen() {
        // 設計書 14 節。10 まで縮め、それでも足りなければ縦に流す。
        let (l, scrolls) = TimelineLayout.fitting(rowCount: 60, height: 180)
        #expect(l.rowHeight == TimelineLayout.minimumRowHeight)
        #expect(scrolls)
    }

    @Test func labelsAppearOnlyWhenTheRowIsTallEnough() {
        // 設計書 8.6。行の高さが 24 を超えると名札の列と帯の中の文字が現れる。
        #expect(!TimelineLayout.fitting(rowCount: 12, height: 180).layout.showsLabels)
        #expect(TimelineLayout.fitting(rowCount: 2, height: 300).layout.showsLabels)
        #expect(TimelineLayout.maximumRowHeight > TimelineLayout.labelThreshold)
    }

    @Test func exactlyTheThresholdDoesNotShowLabels() {
        // 設計書 8.6 は「超えると」であって「以上」ではない。ちょうど 24 では出ない。
        // 8 行・高さ 230 で (230 - 22) / 8 - 2 = 24 ちょうどになる。
        let exact = TimelineLayout.fitting(rowCount: 8, height: 230).layout
        #expect(exact.rowHeight == TimelineLayout.labelThreshold)
        #expect(!exact.showsLabels)
        // 1 点でも高ければ出る。
        let taller = TimelineLayout.fitting(rowCount: 8, height: 231).layout
        #expect(taller.rowHeight > TimelineLayout.labelThreshold)
        #expect(taller.showsLabels)
    }

    @Test func rowAndYAreInverses() {
        let (l, _) = TimelineLayout.fitting(rowCount: 5, height: 300)
        for i in 0..<5 {
            #expect(l.row(atY: l.y(ofRow: i) + l.rowHeight / 2) == i)
        }
    }

    @Test func aPointAboveTheRowsIsNotARow() {
        let (l, _) = TimelineLayout.fitting(rowCount: 5, height: 300)
        #expect(l.row(atY: 2) == nil)
    }

    // MARK: 当たり判定

    @Test func theTickBandGivesTheYearUnderTheFinger() {
        let (l, _) = TimelineLayout.fitting(rowCount: 3, height: 300)
        let t = TimelineTransform(origin: 100, pxPerYear: 2, width: 800)
        let hit = TimelineHit.target(at: CGPoint(x: 200, y: 6), rows: sampleRows(),
                                     layout: l, transform: t, year: 500, worldEnd: world.hi)
        guard case let .ticks(y)? = hit else { Issue.record("目盛りの帯が当たらない: \(String(describing: hit))"); return }
        #expect(abs(y - 200) < 0.001)
    }

    @Test func theCursorWinsOverTheRowBeneathIt() {
        let (l, _) = TimelineLayout.fitting(rowCount: 3, height: 300)
        let t = TimelineTransform(origin: 100, pxPerYear: 2, width: 800)
        // 年 250 の線の上。行 0 の帯（100–300）とも重なるが、線が勝つ。
        let p = CGPoint(x: t.x(of: 250), y: l.y(ofRow: 0) + 2)
        #expect(TimelineHit.target(at: p, rows: sampleRows(), layout: l, transform: t, year: 250, worldEnd: world.hi) == .cursor)
    }

    @Test func aMarkWinsOverTheBandItSitsOn() {
        let (l, _) = TimelineLayout.fitting(rowCount: 3, height: 300)
        let t = TimelineTransform(origin: 100, pxPerYear: 2, width: 800)
        let p = CGPoint(x: t.x(of: 200), y: l.y(ofRow: 0) + l.rowHeight / 2)
        #expect(TimelineHit.target(at: p, rows: sampleRows(), layout: l, transform: t, year: 999, worldEnd: world.hi)
                == .mark("a", 200))
    }

    @Test func aRenameWinsWhenAMarkSitsOnTheSameYear() {
        // 改称の白抜きの菱形は出来事の上に描く。見えているものが当たらなければ嘘になる。
        let (l, _) = TimelineLayout.fitting(rowCount: 3, height: 300)
        let t = TimelineTransform(origin: 100, pxPerYear: 2, width: 800)
        let p = CGPoint(x: t.x(of: 250), y: l.y(ofRow: 0) + l.rowHeight / 2)
        #expect(TimelineHit.target(at: p, rows: sampleRows(), layout: l, transform: t, year: 999, worldEnd: world.hi)
                == .rename("a", 250))
    }

    @Test func theBandItselfWhenNothingElseIsThere() {
        let (l, _) = TimelineLayout.fitting(rowCount: 3, height: 300)
        let t = TimelineTransform(origin: 100, pxPerYear: 2, width: 800)
        let p = CGPoint(x: t.x(of: 120), y: l.y(ofRow: 0) + l.rowHeight / 2)
        #expect(TimelineHit.target(at: p, rows: sampleRows(), layout: l, transform: t, year: 999, worldEnd: world.hi)
                == .row("a"))
    }

    @Test func outsideAnyBandIsNothing() {
        let (l, _) = TimelineLayout.fitting(rowCount: 3, height: 300)
        let t = TimelineTransform(origin: 100, pxPerYear: 2, width: 800)
        // 行 1 は 150 年から。120 年の位置には帯が無い。
        let p = CGPoint(x: t.x(of: 120), y: l.y(ofRow: 1) + l.rowHeight / 2)
        #expect(TimelineHit.target(at: p, rows: sampleRows(), layout: l, transform: t, year: 999, worldEnd: world.hi) == nil)
    }

    @Test func anOpenEndedBandReachesTheRightEdge() {
        let (l, _) = TimelineLayout.fitting(rowCount: 3, height: 300)
        let t = TimelineTransform(origin: 100, pxPerYear: 2, width: 800)
        // 行 1 は 150 年から現在まで。480 年でも帯の上である。
        let p = CGPoint(x: t.x(of: 480), y: l.y(ofRow: 1) + l.rowHeight / 2)
        #expect(TimelineHit.target(at: p, rows: sampleRows(), layout: l, transform: t, year: 999, worldEnd: world.hi) == .row("b"))
    }

    @Test func anOpenEndedBandStopsAtTheWorldEdge() {
        // 帯は世界の右端まで（設計書 6 節）。年カーソルだけがその 10 年先へ行ける。
        // 課題 11 が描く終端と揃っていないと、何も無い場所に板が出る。
        let (l, _) = TimelineLayout.fitting(rowCount: 3, height: 300)
        let t = TimelineTransform(origin: 100, pxPerYear: 2, width: 800)
        let past = CGPoint(x: t.x(of: 800), y: l.y(ofRow: 1) + l.rowHeight / 2)
        #expect(TimelineHit.target(at: past, rows: sampleRows(), layout: l, transform: t,
                                   year: 999, worldEnd: world.hi) == nil)
    }

    @Test func aPointNodeIsHitNearItsYearOnly() {
        let (l, _) = TimelineLayout.fitting(rowCount: 3, height: 300)
        let t = TimelineTransform(origin: 100, pxPerYear: 2, width: 800)
        let onIt = CGPoint(x: t.x(of: 400), y: l.y(ofRow: 2) + l.rowHeight / 2)
        #expect(TimelineHit.target(at: onIt, rows: sampleRows(), layout: l, transform: t, year: 999, worldEnd: world.hi) == .row("c"))
        let away = CGPoint(x: t.x(of: 380), y: l.y(ofRow: 2) + l.rowHeight / 2)
        #expect(TimelineHit.target(at: away, rows: sampleRows(), layout: l, transform: t, year: 999, worldEnd: world.hi) == nil)
    }
}
