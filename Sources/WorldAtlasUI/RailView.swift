import SwiftUI
import WorldAtlasCore

/// 左端の幅 48 のレール。七つの型を縦に並べ、選んだ型に色を付ける（設計書 8.2）。
struct RailView: View {
    @Bindable var store: VaultStore

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Kind.allCases, id: \.self) { k in
                Button {
                    store.kind = k
                } label: {
                    KindIcon(kind: k)
                        .stroke(style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                        .frame(width: 22, height: 22)
                        .padding(7)
                        .foregroundStyle(store.kind == k ? Palette.accent : Color.secondary)
                        .background(store.kind == k ? Palette.accent.opacity(0.12) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help(k.rawValue)
                .accessibilityLabel(k.rawValue)
            }
            Spacer()
        }
        .frame(width: 48)
        .padding(.top, 8)
        .background(.bar)
    }
}
