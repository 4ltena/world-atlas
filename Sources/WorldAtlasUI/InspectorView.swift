import SwiftUI
import WorldAtlasCore
import WorldAtlasStore

/// 右の欄（設計書 8.4）。上に総観を固定し、下を切り替える。
/// **上下に分割しない**——288 の幅で二つの巻物を上下に置くと、どちらも
/// 中途半端な高さになり、総観の文が押し出される（2026-09-08 の試作）。
struct InspectorView: View {
    @Bindable var store: VaultStore

    var body: some View {
        // 材料も総観の状態も一度だけ取る。`overviewState` は取得のたびに材料・入力・
        // digest を組み直し、材料があれば同期でファイルまで読みに行く(VaultStore.swift)。
        // 印と本文が別々に読むと、二つの取得の間に外部更新が挟まったとき、
        // 印と本文が違うファイル状態を指しうる。ここで一度だけ取って両方へ渡す。
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
        // ここには高さの上限を置かない。**短い文の年は自然な高さで止まる**——
        // 上限を VStack の外側に置くと、中の ScrollView が(文が一行でも)
        // 上限いっぱいまで広がり、年の行が上端から沈み、下の一覧の余地を削る
        // （2026-09-08 のレビューで確かめられた欠陥）。上限は伸びうる
        // ScrollView 自身にだけ掛ける。
    }

    /// 本文。**上限は ScrollView 自身に掛ける**——ScrollView は自分から欲張って
    /// 提案された高さいっぱいまで広がる性質があるので、外側の VStack に上限を
    /// 置くと短文でもその上限まで空白ができる。ScrollView の無い三状態には
    /// 上限そのものが無く、内容ぶんだけの高さで止まる。
    @ViewBuilder private func text(_ state: OverviewState, cap: Double) -> some View {
        switch state {
        case let .ready(d), let .stale(d):
            ScrollView {
                Text(d.text).font(.callout).lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
