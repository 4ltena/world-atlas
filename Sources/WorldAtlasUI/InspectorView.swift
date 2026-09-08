import SwiftUI
import WorldAtlasCore
import WorldAtlasStore

/// 右の欄（設計書 8.4）。上に総観を固定し、下を切り替える。
/// **上下に分割しない**——288 の幅で二つの巻物を上下に置くと、どちらも
/// 中途半端な高さになり、総観の文が押し出される（2026-09-08 の試作）。
struct InspectorView: View {
    @Bindable var store: VaultStore

    var body: some View {
        // `overviewState` は一度だけ取り、印と本文の両方へ同じ値を渡す——別々に
        // 呼ぶと、二つの取得の間に外部更新が挟まったとき、印と本文が違う状態を
        // 指しうる。`overviewState` は材料が有る年だけ `.atlas/overview/<年>.md`
        // を読みに行く——`OverviewStore.state(hasMaterial:)` が材料の有無を
        // 先に見て、無ければファイルに触れずに `.noMaterial` を返す
        // (Overview.swift)。一覧に出す材料は `facts` を直に一度だけ取る——
        // `overviewState` が内部で組む材料とは別の取得である。
        let facts = store.facts
        let overviewState = store.overviewState
        // 欄の高さを知るために GeometryReader で囲む。総観の上限は「欄の高さの
        // およそ 45%」（設計書 8.4、2026-09-08 の裁定）であって固定値ではない——
        // 欄の高さは畳んだ年表や窓のリサイズで変わるので、比率で決める。
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 0) {
                overview(overviewState, cap: geo.size.height * 0.45)
                tabs
                switch store.inspectorTab {
                case .events: events(facts)
                case .relations: relations
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Palette.ground)
    }

    // MARK: 総観

    private func overview(_ state: OverviewState, cap: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(store.calendar.format(store.displayedYear))
                    .font(.custom("HiraMinProN-W6", size: 15))
                Spacer(minLength: 4)
                mark(state)
            }
            text(state, cap: cap)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        // 高さの上限そのものは `text` 側に掛けている(下記の註釈)。**ただし、
        // その上限は本文が短くても解消しない**——`.frame(maxHeight: cap)` は、
        // `ViewThatFits` がどちらの候補を選んでも、親の提案が cap より大きければ
        // cap まで広がった値を返す(2026-09-08 round 3 のレビューで確かめられた)。
        // 年の行は上の `HStack` にあり、この `VStack` の先頭で沈まないが、
        // 本文の下に空白が残ることがある——「短文は内容ぶんの高さで止まる」
        // という要件は、この節点では満たせていない。理由は `text(_:cap:)` の
        // 註釈と task-8-report.md の round 3 を見よ。
    }

    /// 本文。**`ViewThatFits` は「収まるか」の選択自体は正しく行う**——短文なら
    /// 裸の `Text`、長文なら `ScrollView` を選ぶ(2026-09-08 round 2 のレビューで
    /// 確かめられた)。**しかし選んだ後の高さまでは制御できない。**
    /// `ViewThatFits` に「cap に収まるか」を正しく判定させるには、外側に
    /// `.frame(maxHeight: cap)` を置いて渡す提案を cap で頭打ちにする必要がある。
    /// ところがこの同じ frame は、選ばれた候補の実寸に関わらず、親の提案が cap
    /// より大きければ cap まで広がった値を返す性質も持つ(round 3 のレビュー)。
    /// つまり cap を外側(ここ)に置けば選択は正しくなるが高さは縮まらず、
    /// `ScrollView` の側だけに掛けて外側を無制限にすれば、今度は判定の基準が
    /// cap でなくなり、長文が「収まる」と誤判定されて下の一覧を押し出しうる
    /// (要件2・4 が壊れる)。SwiftUI の `.frame(maxHeight:)` という一つの仕組みで
    /// 「選択の基準」と「選ばれた後の寸法」を別々に制御することはできない——
    /// これは実機での測定待ちの未確認事項ではなく、この構成が持つ構造的な
    /// 限界だと判断した。ディスプレイなしでこれ以上の構成を確信できないため、
    /// 一覧と切り替えを押し出さない方(要件2・4)を優先し、cap は
    /// `ViewThatFits` 全体に掛けたまま残す。**短文が内容ぶんの高さで止まるという
    /// 要件1は、このため満たしていない。**
    @ViewBuilder private func text(_ state: OverviewState, cap: Double) -> some View {
        switch state {
        case let .ready(d), let .stale(d):
            ViewThatFits(in: .vertical) {
                summary(d.text)
                ScrollView { summary(d.text) }
            }
            .frame(maxHeight: cap, alignment: .top)
        case .missing:
            Text("まだ書いていません").font(.caption).foregroundStyle(.secondary)
        case .generating:
            Text("書いています").font(.caption).foregroundStyle(.secondary)
        case .noMaterial:
            Text("この年の前後に出来事がありません").font(.caption).foregroundStyle(.secondary)
        }
    }

    /// `ViewThatFits` の二つの候補で使う見た目。**同じものを二度書かない。**
    private func summary(_ text: String) -> some View {
        Text(text).font(.callout).lineSpacing(4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 五状態の印（設計書 8.4）。**菱形は使わない**——年表では菱形が出来事と改称を
    /// 意味しているので、同じ形に二つ目の意味を持たせない（2026-09-08 に改めた）。
    @ViewBuilder private func mark(_ state: OverviewState) -> some View {
        switch state {
        case .ready:
            Circle().fill(Color.secondary).frame(width: 9, height: 9)
                .accessibilityLabel("生成済み")
        case .stale:
            Circle().fill(Color.secondary).frame(width: 9, height: 9)
                .mask(alignment: .leading) { Rectangle().frame(width: 4.5) }
                .overlay { Circle().stroke(Color.secondary, lineWidth: 1.5) }
                .accessibilityLabel("古い")
        case .missing:
            Circle().stroke(Color.secondary, lineWidth: 1.5).frame(width: 9, height: 9)
                .accessibilityLabel("未生成")
        case .generating:
            ProgressView().controlSize(.mini).accessibilityLabel("生成中")
        case .noMaterial:
            EmptyView()
        }
    }

    // MARK: 切り替え

    private var tabs: some View {
        Picker("", selection: Binding(get: { store.inspectorTab },
                                      set: { store.inspectorTab = $0 })) {
            Text("この年のできごと").tag(VaultStore.InspectorTab.events)
            Text("関連").tag(VaultStore.InspectorTab.relations)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    // MARK: この年のできごと

    private func events(_ facts: [Fact]) -> some View {
        List(Array(facts.enumerated()), id: \.offset) { _, f in
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(store.calendar.short(f.year))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 30, alignment: .trailing)
                VStack(alignment: .leading, spacing: 1) {
                    Text(f.display).font(.callout)
                    if !f.text.isEmpty {
                        Text(f.text).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture { store.requestSelect(f.path) }
            .listRowInsets(EdgeInsets(top: 3, leading: 12, bottom: 3, trailing: 12))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay {
            if facts.isEmpty {
                Text("前後 12 年に何もありません").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: 関連

    private var relations: some View {
        List {
            ForEach(store.relations) { g in
                Section(g.title) {
                    ForEach(g.nodes) { n in
                        HStack(spacing: 6) {
                            Text(n.name).font(.callout)
                            Spacer(minLength: 4)
                            if !n.note.isEmpty {
                                Text(n.note).font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        // その年に存在しない節点は薄く出す（設計書 8.4）。
                        .opacity(n.absent ? 0.45 : 1)
                        .contentShape(Rectangle())
                        .onTapGesture { store.requestSelect(n.path) }
                        .listRowInsets(EdgeInsets(top: 3, leading: 12, bottom: 3, trailing: 12))
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay {
            if store.relations.isEmpty {
                Text(store.selected == nil ? "節点を選ぶと出ます" : "関連がありません")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
