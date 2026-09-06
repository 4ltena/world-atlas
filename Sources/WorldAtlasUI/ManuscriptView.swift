import SwiftUI
import WorldAtlasCore

/// 原稿の欄。上に「表示」と「原文」の区分けを置く（設計書 8.3）。
/// Stage 2 の原文は読むだけで、編集と ⌘S はStage 4 で足す。
struct ManuscriptView: View {
    @Bindable var store: VaultStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Picker("", selection: Binding(get: { store.showsRawEffectively },
                                              set: { store.showsRaw = $0 })) {
                    Text("表示").tag(false)
                    Text("原文").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                // 壊れた節点は原文だけが使える（設計書 4.4）。
                .disabled(store.isBroken)
                if store.isBroken {
                    Text("front matter が読めないので原文だけを出しています")
                        .font(.caption).foregroundStyle(Palette.warning)
                }
            }
            .padding(10)
            Rectangle().fill(Palette.rule).frame(height: 1)
            if store.showsRawEffectively { raw } else { rendered }
        }
        .background(Palette.ground)
    }

    private var raw: some View {
        ScrollView {
            Text(store.raw)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 40)
                .padding(.vertical, 32)
        }
        .background(Palette.ground)
    }

    @ViewBuilder private var rendered: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let e = store.textError {
                    Label(e, systemImage: "exclamationmark.triangle").foregroundStyle(Palette.warning)
                }
                if let h = store.header {
                    header(h)
                } else if store.text.isEmpty {
                    Text("世界.md に書くと、ここに出ます").foregroundStyle(.secondary)
                }
                ForEach(store.blocks) { block($0) }
            }
            .tint(Palette.accent)
            .textSelection(.enabled)
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, 40)
            .padding(.vertical, 32)
        }
    }

    private func header(_ h: Header) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                ForEach(Array(h.crumbs.enumerated()), id: \.element.id) { i, c in
                    if i > 0 { Text("›").foregroundStyle(.tertiary) }
                    Button(c.name) { store.select(c.path) }
                        .buttonStyle(.plain)
                        .foregroundStyle(i == h.crumbs.count - 1 ? Color.primary : Color.secondary)
                }
            }
            .font(.caption)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(h.title).font(.custom("HiraMinProN-W6", size: 26))
                if let saved = h.savedName {
                    Text(saved).font(.caption).foregroundStyle(.secondary)
                }
                ForEach(h.flags, id: \.self) { f in
                    Label(f.rawValue, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(Palette.warning)
                }
            }

            HStack(spacing: 8) {
                chip("種別", h.category)
                ForEach(h.chips) { chip($0.label, $0.value) }
            }
            Rectangle().fill(Palette.rule).frame(height: 1).padding(.top, 4)
        }
    }

    private func chip(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(.secondary)
            Text(value)
        }
        .font(.caption)
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(Palette.veil, in: Capsule())
    }

    @ViewBuilder private func block(_ b: RenderedBlock) -> some View {
        switch b.style {
        case let .heading(level):
            Text(b.lines[0])
                .font(.custom("HiraMinProN-W6", size: level == 1 ? 22 : level == 2 ? 18 : 15))
                .padding(.top, 8)
        case .bullet:
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(b.lines.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("・").foregroundStyle(.secondary)
                        Text(line)
                    }
                }
            }
        case .paragraph:
            Text(b.lines[0]).lineSpacing(7)
        }
    }
}
