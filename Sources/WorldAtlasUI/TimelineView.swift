import SwiftUI
import WorldAtlasCore

/// 下段の年表（設計書 8.6）。判断は Timeline* の値型が持ち、ここは描いて触るだけ。
/// この課題では描くところまでを作る。触るのは課題 12。
struct TimelineView: View {
    @Bindable var store: VaultStore

    /// 行を縦に流した量。0 が先頭。**課題 12 が動かす。この課題では常に 0 である。**
    @State private var rowScroll: Double = 0

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
                   scrolls: scrolls, size: geo.size)
                .contentShape(Rectangle())
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
                    rowScroll = min(rowScroll, maxScroll(layout: layout, rowCount: rows.count, height: h))
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

    // MARK: 描く

    private func canvas(rows: [TimelineRow], layout: TimelineLayout,
                        transform t: TimelineTransform, scrollY: Double,
                        scrolls: Bool, size: CGSize) -> some View {
        Canvas { ctx, _ in
            let span = t.origin...(t.origin + t.years)
            let interval = TimelineTicks.interval(pxPerYear: t.pxPerYear)
            // 帯の右端。年カーソルだけが 10 年先まで行ける（設計書 6 節）。
            let worldEnd = store.snapshot.extent.hi

            // 目盛りの帯。流さない。
            for y in TimelineTicks.years(in: span, interval: interval) {
                let x = t.x(of: Double(y))
                ctx.stroke(Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: size.height)) },
                           with: .color(Palette.rule), lineWidth: 1)
                ctx.draw(Text(store.calendar.format(y)).font(.caption2).foregroundColor(.secondary),
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
                if store.showsRuleStripes {
                    for rule in r.rules {
                        let a = t.x(of: Double(rule.from))
                        let b = t.x(of: Double(rule.to ?? worldEnd))
                        let k = store.polityIndices[rule.polity] ?? 0
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

                // 名札は行が高いときだけ出す（設計書 8.6）。
                if layout.showsLabels {
                    rowsCtx.draw(Text(r.name).font(.caption).foregroundColor(.primary),
                                 at: CGPoint(x: x0 + 6, y: mid), anchor: .leading)
                }
            }

            // 年カーソル。いちばん上に描く。地色の縁を付けて、どの色帯の上でも線として読めるようにする
            // （朱は勢力の五色と近いことがあり、色の差では分けられない）。
            let cx = t.x(of: Double(store.displayedYear))
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
