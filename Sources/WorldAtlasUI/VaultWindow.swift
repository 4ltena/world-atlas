import SwiftUI
import WorldAtlasStore

/// vault ひとつぶんの窓。上段に木と原稿、下段に年表を置く。
public struct VaultWindow: View {
    @State private var store: VaultStore
    @State private var newName = ""

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
                    .inspector(isPresented: Binding(get: { store.showsInspector },
                                                    set: { store.showsInspector = $0 })) {
                        InspectorView(store: store)
                            .inspectorColumnWidth(min: 240, ideal: 288, max: 420)
                    }
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
        .onDisappear {
            Task { await store.stop() }
            OpenVaults.forget(store)
        }
        .background(WindowCloseGuard(shouldClose: { store.requestClose() },
                                     wantsClose: store.wantsClose,
                                     onWindow: { OpenVaults.register(store, window: $0) }))
        .focusedSceneValue(\.vaultStore, store)
        .environment(\.openURL, OpenURLAction { url in
            // 自分のスキームは必ず自分で受ける。解決先が無ければ何もしない。
            guard let path = NodeURL.path(from: url) else { return .systemAction }
            if store.snapshot.nodes[path] != nil {
                store.requestSelect(path, arrivedAs: NodeURL.arrivedName(from: url))
            }
            return .handled
        })
        .overlay {
            if let e = store.loadError {
                ContentUnavailableView("この vault を読めません", systemImage: "exclamationmark.triangle", description: Text(e))
            }
        }
        .confirmationDialog("保存していない変更があります",
                            // **消すのは三つのボタンだけ。**閉じる側の setter で
                            // `passageCancel()` を呼ぶと、保存に失敗して意図的に残した
                            // 問いまで消える(設計書 8.3 は出し直せと言っている)。さらに
                            // SwiftUI は setter とボタンの動作の順序を約束しないので、先に
                            // 消えると「保存せず移る」が編集を捨てたまま移動しない。
                            // Esc は role: .cancel のボタンを呼ぶので、そちらで消える。
                            isPresented: Binding(get: { store.pendingPassage != nil },
                                                 set: { _ in }),
                            titleVisibility: .visible) {
            Button("保存して移る") { store.passageSaveAndGo() }
            Button("保存せず移る", role: .destructive) { store.passageDiscardAndGo() }
            Button("やめる", role: .cancel) { store.passageCancel() }
        } message: {
            Text("「保存せず移る」を選ぶと、いまの編集は失われます。")
        }
        .sheet(isPresented: Binding(get: { store.creating },
                                    set: { store.creating = $0 })) {
            VStack(alignment: .leading, spacing: 14) {
                Text("新しい\(store.kind.rawValue)").font(.headline)
                TextField("名前", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                if let e = store.creationError {
                    Text(e).font(.caption).foregroundStyle(Palette.warning)
                }
                HStack {
                    Spacer()
                    Button("やめる", role: .cancel) { store.cancelCreating(); newName = "" }
                    Button("作る") { if store.createNode(named: newName) { newName = "" } }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .background(Palette.ground)
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
