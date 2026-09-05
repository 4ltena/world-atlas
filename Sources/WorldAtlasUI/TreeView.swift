import SwiftUI
import WorldAtlasCore

/// 木の上の「選択中の欄」と、木そのもの（設計書 8.2）。
struct TreeView: View {
    @Bindable var store: VaultStore

    private var selection: Binding<String?> {
        Binding(get: { store.selected }, set: { store.select($0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            selectedBar
            Divider()
            List(selection: selection) {
                ForEach(store.rows) { TreeRow(node: $0, store: store) }
            }
            .listStyle(.sidebar)
            .overlay { if store.rows.isEmpty { empty } }
        }
    }

    /// いま選んでいる節点の名前と種別。行ごとにタグを付ける代わりの欄。
    private var selectedBar: some View {
        HStack(spacing: 6) {
            if let h = store.header {
                Text(h.title).font(.headline)
                Text(h.category).font(.caption).foregroundStyle(.secondary)
            } else {
                Text("選んでいません").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var empty: some View {
        // 「⌘N で作る」の後半はStage 4 で作成ができるようになってから足す（設計書 14 節）。
        Text(store.query.isEmpty ? "まだ項目が無い" : "該当なし")
            .font(.callout)
            .foregroundStyle(.secondary)
    }
}

/// 木の一行。子があれば畳める。折り畳みは選択とは独立に動く（設計書 8.2）。
struct TreeRow: View {
    let node: TreeNode
    @Bindable var store: VaultStore

    private var isExpanded: Binding<Bool> {
        Binding(get: { store.expanded.contains(node.path) },
                set: { newValue in
                    if newValue { store.expanded.insert(node.path) }
                    else { store.expanded.remove(node.path) }
                })
    }

    var body: some View {
        if node.children.isEmpty {
            label
        } else {
            DisclosureGroup(isExpanded: isExpanded) {
                ForEach(node.children) { TreeRow(node: $0, store: store) }
            } label: {
                label
            }
        }
    }

    private var label: some View {
        HStack(spacing: 4) {
            Text(node.name)
            Spacer(minLength: 4)
            if !node.flags.isEmpty {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(Palette.warning)
                    .help(Manuscript.flagOrder.filter { node.flags.contains($0) }
                        .map(\.rawValue).joined(separator: "、"))
            }
        }
        .tag(node.path)
    }
}
