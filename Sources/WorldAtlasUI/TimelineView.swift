import SwiftUI
import WorldAtlasCore

/// 下段の年表（設計書 8.6）。判断は Timeline* の値型が持ち、ここは描いて触るだけ。
/// この課題では描くところまでを作る。触るのは課題 12。
struct TimelineView: View {
    @Bindable var store: VaultStore

    /// 行を縦に流した量。0 が先頭。**課題 12 が動かす。この課題では常に 0 である。**
    @State private var rowScroll: Double = 0

    /// いま何をしている最中か。掴み始め（ピンチ始め）に一つ決めて、終わるまで変えない。
    private enum Interaction { case year, rows, pan, zoom }
    @State private var interaction: Interaction?
    /// 操作を始めたときの尺。操作中はここから作る。
    @State private var gestureBase: TimelineTransform?
    /// 縦に流し始めたときの位置。
    @State private var scrollBase: Double = 0

    /// 相手が用途を握っている間に押されていた側。自分が一度離すまで黙る。
    @State private var dragBlocked = false
    @State private var pinchBlocked = false

    @State private var hovering: TimelineHit.Target?
    @State private var hoverPoint: CGPoint = .zero

    var body: some View {
        GeometryReader { geo in
            let rows = store.timelineRows
            let (layout, scrolls) = TimelineLayout.fitting(rowCount: rows.count, height: geo.size.height)
            let t = store.scale ?? .whole(width: geo.size.width, limits: store.snapshot.extent)
            // **描くときに毎回押し込める。** 高さを広げて全行が収まると縦の掴みが効かなくなるので、
            // 流した量を状態のまま信じると、先頭を切った位置から戻れなくなる。
            let scrollY = min(rowScroll, maxScroll(layout: layout, rowCount: rows.count,
                                                   height: geo.size.height))

            canvas(rows: rows, layout: layout, transform: t, scrollY: scrollY,
                   scrolls: scrolls, size: geo.size,
                   worldEnd: store.snapshot.extent.hi, calendar: store.calendar,
                   showsRuleStripes: store.showsRuleStripes, polityIndices: store.polityIndices,
                   year: store.displayedYear)
                .contentShape(Rectangle())
                .gesture(SimultaneousGesture(dragGesture(size: geo.size, layout: layout, scrolls: scrolls,
                                                         rowCount: rows.count),
                                             pinchGesture(size: geo.size)))
                // 二本指の横スワイプとホイール（設計書 8.6）。掴みやピンチの最中は受けない。
                .modifier(ScrollPanReader(frame: geo.frame(in: .global)) { dx in
                    guard interaction == nil else { return }
                    let base = store.scale
                        ?? .whole(width: geo.size.width, limits: store.snapshot.extent)
                    store.setScale(base.panned(byX: dx, limits: store.snapshot.extent))
                })
                .onContinuousHover { phase in
                    switch phase {
                    case let .active(p):
                        hoverPoint = p
                        // 行は流れているので、判定へ渡す前に流した分を戻す。
                        // 目盛りの帯の中は流れないので、そのまま渡す。
                        let q = p.y >= TimelineLayout.tickHeight
                            ? CGPoint(x: p.x, y: p.y + scrollY) : p
                        hovering = TimelineHit.target(at: q, rows: rows, layout: layout,
                                                      transform: t, year: store.displayedYear,
                                                      worldEnd: store.snapshot.extent.hi)
                    case .ended:
                        hovering = nil
                    }
                }
                .overlay(alignment: .topLeading) { hoverCard(rows: rows) }
                .onAppear {
                    store.ensureScale(width: geo.size.width)
                    // 畳んでいる間に立った頼みをここで片づける。onChange は値が
                    // 変わったときにしか鳴らないので、出てきた時点で見に行く必要がある。
                    consumeRequest(width: geo.size.width)
                }
                // 窓は読み込みを待たずに一度組まれる。索引が済んで世界の名前が入った時点で、
                // 空の端で決まりかけていた尺を当てはめ直す（VaultStore.ensureScale の注記）。
                .onChange(of: store.snapshot.world.name) { _, _ in
                    store.ensureScale(width: geo.size.width)
                    // 読み込み中に押されて取っておいた頼みを、ここで実行する。
                    consumeRequest(width: geo.size.width)
                }
                .onChange(of: geo.size.width) { _, w in store.ensureScale(width: w) }
                // 境目を掴んで変わった高さを覚えへ写す。畳んで開き直したときにこの高さで戻る。
                .onChange(of: geo.size.height) { _, h in
                    store.setTimelineHeight(h)
                }
                .onChange(of: store.scaleRequest) { _, _ in consumeRequest(width: geo.size.width) }
                .onChange(of: rows.count) { _, _ in rowScroll = 0 }
        }
        .background(Palette.ground)
    }

    /// 「合わせる」「全体」の頼みを片づける。年ゲージの行とメニューは幅を知らないので印だけを
    /// 立て、幅を持っているこちらが実行する。**畳んでいる間に立った印もここで消える。**
    private func consumeRequest(width: Double) {
        // **読み込み中は片づけない。**印を残しておき、索引が済んだ時点で実行する。
        // ここで消すと、読み込み中に押した「合わせる」がどこへも行かずに消える。
        guard store.isLoaded else { return }
        switch store.scaleRequest {
        case .fit: store.fitScale(width: width)
        case .whole: store.showWholeWorld(width: width)
        case nil: return
        }
        store.clearScaleRequest()
    }

    /// 縦に流せる余地。行が収まっていれば 0。
    func maxScroll(layout: TimelineLayout, rowCount: Int, height: Double) -> Double {
        let content = layout.tickHeight + Double(rowCount) * (layout.rowHeight + layout.rowGap)
        return max(content - height, 0)
    }

    // MARK: 触る

    /// `maxScroll` は課題 11 が置いたものを使う。掴める幅も課題 8 の `TimelineHit.grab` を使う。
    /// **同じ数を二箇所に書かない。**

    /// 掴み。用途は掴み始めに一つ決め、離すまで変えない。
    private func dragGesture(size: CGSize, layout: TimelineLayout,
                             scrolls: Bool, rowCount: Int) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                // 相手が用途を握っている間は、こちらは何もしない。相手が離した後も、
                // 自分が一度離すまで黙る。**でないと、相手の終わりで印が消えた瞬間に、
                // 掴み始めからの累積の移動量を新しい基準へ当てて尺が跳ぶ。**
                if let i = interaction, i == .zoom { dragBlocked = true }
                if dragBlocked { return }

                let base = gestureBase ?? store.scale
                    ?? .whole(width: size.width, limits: store.snapshot.extent)
                if gestureBase == nil { gestureBase = base }

                if interaction == nil {
                    // 年カーソルの線の位置は store.year で見る。掴んでいる間これは動かない。
                    if v.startLocation.y < TimelineLayout.tickHeight
                        || abs(v.startLocation.x - base.x(of: Double(store.year))) <= TimelineHit.grab {
                        interaction = .year
                    } else if abs(v.translation.height) > abs(v.translation.width),
                              abs(v.translation.height) > 3, scrolls {
                        interaction = .rows
                        scrollBase = rowScroll
                    } else if abs(v.translation.width) > 3 {
                        interaction = .pan
                    }
                }

                switch interaction {
                case .year:
                    let e = store.snapshot.extent
                    store.draggingYear = min(max(Int(base.year(atX: v.location.x).rounded()), e.lo), e.hi + 10)
                case .rows:
                    let limit = maxScroll(layout: layout, rowCount: rowCount, height: size.height)
                    rowScroll = min(max(scrollBase - v.translation.height, 0), limit)
                case .pan:
                    store.setScale(base.panned(byX: Double(v.translation.width), limits: store.snapshot.extent))
                default:
                    break   // .zoom がピンチに取られている間、掴みは何もしない
                }
            }
            .onEnded { _ in
                dragBlocked = false
                // ピンチが用途を握っているときだけ、こちらは何も片づけない。
                // **用途が決まらないまま離したとき（押しただけ）も片づける。**
                // 掴み始めに base を控えているので、残すと次の操作が古い尺から始まって跳ぶ。
                guard interaction != .zoom else { return }
                if interaction == .year, let y = store.draggingYear {
                    // ここで初めて木と原稿の呼び名が切り替わる（設計書 8.6）。
                    store.setYear(y)
                }
                store.draggingYear = nil
                finishInteraction()
            }
    }

    private func pinchGesture(size: CGSize) -> some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { v in
                if let i = interaction, i != .zoom { pinchBlocked = true }
                if pinchBlocked { return }

                let base = gestureBase ?? store.scale
                    ?? .whole(width: size.width, limits: store.snapshot.extent)
                if gestureBase == nil { gestureBase = base }
                if interaction == nil { interaction = .zoom }
                guard interaction == .zoom else { return }
                store.setScale(base.zoomed(by: Double(v.magnification), aroundX: size.width / 2,
                                           limits: store.snapshot.extent))
            }
            .onEnded { _ in
                pinchBlocked = false
                if interaction == .zoom { finishInteraction() }
            }
    }

    private func finishInteraction() {
        interaction = nil
        gestureBase = nil
    }

    // MARK: 乗せたときの板

    @ViewBuilder private func hoverCard(rows: [TimelineRow]) -> some View {
        if let h = hovering, let text = cardText(h, rows: rows) {
            Text(text)
                .font(.caption)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Palette.sidebar, in: RoundedRectangle(cornerRadius: 4))
                .offset(x: hoverPoint.x + 10, y: hoverPoint.y - 26)
                .allowsHitTesting(false)
        }
    }

    /// 板に出す文字。設計書 8.6 は要約も挙げているが、Snapshot は本文を持たないので
    /// この段では名前・種別・期間だけを出す（末尾の「この段では作らないもの」）。
    ///
    /// **年はすべて選んだ暦で出す**（設計書 6 節）。目盛りが海都暦 496 年を指しているのに
    /// 板が 318 と言うと読み違える。暦名を二度出さないよう、期間は `short` を使い、
    /// 暦名は先頭に一度だけ置く。
    private func cardText(_ h: TimelineHit.Target, rows: [TimelineRow]) -> String? {
        let c = store.calendar
        switch h {
        case let .row(path):
            guard let r = rows.first(where: { $0.path == path }) else { return nil }
            let head = "\(r.name)（\(r.category)）\(c.name) "
            if r.isPoint { return head + "\(c.short(r.from)) 年" }
            guard let to = r.to else { return head + "\(c.short(r.from)) 年から現在" }
            return head + "\(c.short(r.from))–\(c.short(to)) 年"
        case let .mark(path, year):
            guard let r = rows.first(where: { $0.path == path }),
                  let m = r.marks.first(where: { $0.year == year }) else { return nil }
            return "\(c.format(year)) \(m.label)"
        case let .rename(path, year):
            guard let r = rows.first(where: { $0.path == path }),
                  let a = r.renames.first(where: { $0.from == year }) else { return nil }
            return "\(c.format(year)) \(a.name) へ改称"
        case .ticks, .cursor:
            return nil
        }
    }

    // MARK: 描く

    private func canvas(rows: [TimelineRow], layout: TimelineLayout,
                        transform t: TimelineTransform, scrollY: Double,
                        scrolls: Bool, size: CGSize,
                        worldEnd: Int, calendar: CalendarDef,
                        showsRuleStripes: Bool, polityIndices: [String: Int],
                        year: Int) -> some View {
        Canvas { ctx, _ in
            let span = t.origin...(t.origin + t.years)
            let interval = TimelineTicks.interval(pxPerYear: t.pxPerYear)

            // 目盛りの帯。流さない。
            for y in TimelineTicks.years(in: span, interval: interval) {
                let x = t.x(of: Double(y))
                ctx.stroke(Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: size.height)) },
                           with: .color(Palette.rule), lineWidth: 1)
                // 暦名は年ゲージの行に一度だけ出る。目盛りには数だけを置く。
                ctx.draw(Text(calendar.short(y)).font(.caption2).foregroundColor(.secondary),
                         at: CGPoint(x: x + 4, y: 11), anchor: .leading)
            }

            // 行は目盛りの帯の下だけに描く。流しても目盛りに被らない。
            var rowsCtx = ctx
            rowsCtx.clip(to: Path(CGRect(x: 0, y: layout.tickHeight,
                                         width: size.width, height: max(size.height - layout.tickHeight, 0))))

            for (i, r) in rows.enumerated() {
                let top = layout.y(ofRow: i) - scrollY
                let h = layout.rowHeight
                guard top + h >= layout.tickHeight, top <= size.height else { continue }
                let x0 = t.x(of: Double(r.from))
                let x1 = r.isPoint ? x0 : t.x(of: Double(r.to ?? worldEnd))

                // 存続期間の帯。自身の段は朱、子は霞。点の節点には帯が無い。
                if !r.isPoint {
                    let band = CGRect(x: x0, y: top, width: max(x1 - x0, 1), height: h * 0.62)
                    rowsCtx.fill(Path(roundedRect: band, cornerRadius: 2),
                                 with: .color(r.isRoot ? Palette.accent.opacity(0.55) : Palette.veil))
                }

                // 支配の色帯。帯の下に 2 ポイント。色だけに頼らず模様も変える（設計書 10 節）。
                if showsRuleStripes {
                    for rule in r.rules {
                        let a = t.x(of: Double(rule.from))
                        let b = t.x(of: Double(rule.to ?? worldEnd))
                        let k = polityIndices[rule.polity] ?? 0
                        let y = top + h * 0.62 + 2
                        // 勢力が替わる位置に 1 ポイントの切れ目（設計書 8.6）。右端だけを削る。
                        // 両端を 1 ずつ削ると、隣り合う帯のあいだが 2 ポイント空く。
                        var p = Path()
                        p.move(to: CGPoint(x: a, y: y))
                        p.addLine(to: CGPoint(x: max(b - 1, a), y: y))
                        rowsCtx.stroke(p, with: .color(Palette.polity(k)),
                                       style: StrokeStyle(lineWidth: 2, dash: Palette.polityDash(k)))
                    }
                }

                // 由来の線。
                for l in r.lineages {
                    let x = t.x(of: Double(l.year))
                    rowsCtx.stroke(Path { $0.move(to: CGPoint(x: x, y: top)); $0.addLine(to: CGPoint(x: x, y: top + h)) },
                                   with: .color(Palette.rule), lineWidth: 1)
                }

                // 出来事は塗りの菱形、改称は白抜きの菱形。改称を後に描くので上に乗る。
                // 点の節点そのものも塗りの菱形で出す。marks には入っていないので、
                // ここで描かなければ行がまるごと空白になる。
                let mid = top + h * 0.31
                if r.isPoint { diamond(rowsCtx, at: CGPoint(x: x0, y: mid), filled: true) }
                for m in r.marks { diamond(rowsCtx, at: CGPoint(x: t.x(of: Double(m.year)), y: mid), filled: true) }
                for a in r.renames { diamond(rowsCtx, at: CGPoint(x: t.x(of: Double(a.from)), y: mid), filled: false) }

                // 名札は行が高いときだけ出す（設計書 8.6）。**帯の左端が画面の外にあっても、
                // 帯が見えている限り名札は出す。**寄せると x0 は大きな負の数になる。
                if layout.showsLabels, x1 > 0, x0 < size.width {
                    rowsCtx.draw(Text(r.name).font(.caption).foregroundColor(.primary),
                                 at: CGPoint(x: max(x0 + 6, 6), y: mid), anchor: .leading)
                }
            }

            // 年カーソル。いちばん上に描く。地色の縁を付けて、どの色帯の上でも線として読めるようにする
            // （朱は勢力の五色と近いことがあり、色の差では分けられない）。
            let cx = t.x(of: Double(year))
            let line = Path { $0.move(to: CGPoint(x: cx, y: 0)); $0.addLine(to: CGPoint(x: cx, y: size.height)) }
            ctx.stroke(line, with: .color(Palette.ground), lineWidth: 3)
            ctx.stroke(line, with: .color(Palette.accent), lineWidth: 1)

            if scrolls {
                ctx.draw(Text("縦に引くと続きが出ます").font(.caption2).foregroundColor(.secondary),
                         at: CGPoint(x: size.width - 6, y: size.height - 8), anchor: .trailing)
            }
        }
    }

    private func diamond(_ ctx: GraphicsContext, at p: CGPoint, filled: Bool) {
        let r = 4.0
        let path = DiamondShape().path(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        if filled { ctx.fill(path, with: .color(Palette.accent)) }
        else {
            ctx.fill(path, with: .color(Palette.ground))
            ctx.stroke(path, with: .color(Palette.accent), lineWidth: 1)
        }
    }
}
