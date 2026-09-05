import SwiftUI
import WorldAtlasStore

/// vault ひとつぶんの窓。上段だけを作る。下段の年表はStage 3 で足す。
public struct VaultWindow: View {
    @State private var store: VaultStore

    public init(vault: URL) {
        _store = State(initialValue: VaultStore(vault: vault))
    }

    public var body: some View {
        NavigationSplitView {
            HStack(spacing: 0) {
                RailView(store: store)
                Divider()
                TreeView(store: store)
            }
            .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 460)
        } detail: {
            ManuscriptView(store: store)
        }
        .searchable(text: $store.query, placement: .toolbar, prompt: "名前で絞り込む")
        .navigationTitle(store.snapshot.world.name.isEmpty ? "world-atlas" : store.snapshot.world.name)
        .task { await store.load() }
        .onDisappear { Task { await store.stop() } }
        .focusedSceneValue(\.vaultStore, store)
        .overlay {
            if let e = store.loadError {
                ContentUnavailableView("この vault を読めません", systemImage: "exclamationmark.triangle", description: Text(e))
            }
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
