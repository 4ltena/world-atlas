import SwiftUI
import WorldAtlasStore

/// vault ひとつぶんの窓。上段に木と原稿、下段に年表を置く。
public struct VaultWindow: View {
    @State private var store: VaultStore

    public init(vault: URL) {
        _store = State(initialValue: VaultStore(vault: vault))
    }

    public var body: some View {
        VSplitView {
            NavigationSplitView {
                HStack(spacing: 0) {
                    RailView(store: store)
                    TreeView(store: store)
                }
                .background(Palette.sidebar)
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 460)
            } detail: {
                ManuscriptView(store: store)
            }
            .frame(minHeight: 240)

            VStack(spacing: 0) {
                YearGaugeView(store: store,
                              onFit: { store.requestRefit() },
                              onWhole: { store.requestWhole() })
                if !store.timelineCollapsed {
                    // **高さを固定しない。** VSplitView の境目で高さが変わり、その高さで行が太る。
                    // 固定すると設計書 8.6 の「境目を掴んで行の高さが 24 を超えると名札が出る」に
                    // 永久に届かない。store.timelineHeight は畳んで開いたときに戻すための覚えで、
                    // 実測した高さを TimelineView が書き戻す。
                    TimelineView(store: store)
                        .frame(minHeight: 120, idealHeight: store.timelineHeight)
                }
            }
        }
        .searchable(text: $store.query, placement: .toolbar, prompt: "名前で絞り込む")
        .navigationTitle(store.snapshot.world.name.isEmpty ? "world-atlas" : store.snapshot.world.name)
        .navigationSubtitle(store.timelineSubtitle)
        .task { await store.load() }
        .onDisappear { Task { await store.stop() } }
        .focusedSceneValue(\.vaultStore, store)
        .environment(\.openURL, OpenURLAction { url in
            // 自分のスキームは必ず自分で受ける。解決先が無ければ何もしない。
            guard let path = NodeURL.path(from: url) else { return .systemAction }
            if store.snapshot.nodes[path] != nil { store.requestSelect(path) }
            return .handled
        })
        .overlay {
            if let e = store.loadError {
                ContentUnavailableView("この vault を読めません", systemImage: "exclamationmark.triangle", description: Text(e))
            }
        }
        .confirmationDialog("保存していない変更があります",
                            isPresented: Binding(get: { store.pendingPassage != nil },
                                                 set: { if !$0 { store.passageCancel() } }),
                            titleVisibility: .visible) {
            Button("保存して移る") { store.passageSaveAndGo() }
            Button("保存せず移る", role: .destructive) { store.passageDiscardAndGo() }
            Button("やめる", role: .cancel) { store.passageCancel() }
        } message: {
            Text("「保存せず移る」を選ぶと、いまの編集は失われます。")
        }
    }
}

/// メニューが「いま前にある窓の store」を読むための鍵（課題 12 で使う）。
struct VaultStoreKey: FocusedValueKey {
    typealias Value = VaultStore
}

extension FocusedValues {
    var vaultStore: VaultStore? {
        get { self[VaultStoreKey.self] }
        set { self[VaultStoreKey.self] = newValue }
    }
}
