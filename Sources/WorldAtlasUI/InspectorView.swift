import SwiftUI
import WorldAtlasCore
import WorldAtlasStore

/// 右の欄（設計書 8.4）。上に総観を固定し、下を切り替える。
/// **上下に分割しない**——288 の幅で二つの巻物を上下に置くと、どちらも
/// 中途半端な高さになり、総観の文が押し出される（2026-09-08 の試作）。
struct InspectorView: View {
    @Bindable var store: VaultStore

    var body: some View {
        // 材料は一度だけ取る。`overviewState` も内部で同じものを組み立てるので、
        // 巻きのたびに二度走らせない。
        let facts = store.facts
        VStack(alignment: .leading, spacing: 0) {
            overview
            tabs
            switch store.inspectorTab {
            case .events: events(facts)
            case .relations: relations
            }
        }
        .background(Palette.ground)
    }

    // MARK: 総観

    private var overview: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(store.calendar.format(store.displayedYear))
                    .font(.custom("HiraMinProN-W6", size: 15))
                Spacer(minLength: 4)
                mark
            }
            text
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        // 固定する高さの上限。文が長くても、下の切り替えを押し出さない（設計書 8.4）。
        .frame(maxHeight: 260)
    }

    @ViewBuilder private var text: some View {
        switch store.overviewState {
        case let .ready(d), let .stale(d):
            ScrollView {
                Text(d.text).font(.callout).lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
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
    @ViewBuilder private var mark: some View {
        switch store.overviewState {
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
