import SwiftUI

/// この段で動く操作だけをメニューに置く（設計書 8.1）。
/// 残るのは右の欄 ⌥⌘I（Stage 5）と設定 ⌘,（Stage 6）だけである。
public struct AppCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.vaultStore) private var store

    public init() {}

    public var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("新規項目…") { store?.creating = true }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(store == nil)

            // 開くのも新規作成も一覧の窓から行うので、ここはその窓を前に出すだけである。
            // フォルダ選択を直接出す道は持たない（設計書 4.1、8.1）。
            Button("vault の一覧") { openWindow(id: "vaults") }
                .keyboardShortcut("o", modifiers: .command)
        }
        CommandGroup(replacing: .saveItem) {
            Button("保存") { store?.save() }
                .keyboardShortcut("s", modifiers: .command)
                // 書くものが無いときは押せない。`canSave` を使う——`isDirty` だけだと、
                // 外の変更を知らせている状態で文字列を戻したときに、帯が「⌘S で上書き」と
                // 言っているのに押せなくなる。壊れた節点も原文で編集できるので塞がない。
                .disabled(store == nil || !(store?.canSave ?? false))
        }
        CommandMenu("表示") {
            Button(store?.showsRawEffectively == true ? "表示に切り替える" : "原文に切り替える") {
                store?.showsRaw.toggle()
            }
            .keyboardShortcut("e", modifiers: [.option, .command])
            // 壊れた節点は原文だけが使えるので、切り替えられない（設計書 4.4）。
            .disabled(store == nil || store?.isBroken == true)

            Button(store?.timelineCollapsed == true ? "年表を表示" : "年表を隠す") {
                store?.timelineCollapsed.toggle()
            }
            .keyboardShortcut("t", modifiers: [.option, .command])
            .disabled(store == nil)

            // 設計書 8.1 の表では短縮キーを持たない。
            Toggle("支配の色帯", isOn: Binding(get: { store?.showsRuleStripes ?? false },
                                          set: { store?.showsRuleStripes = $0 }))
                .disabled(store == nil)

            // 尺は幅を持つ TimelineView が動かすので、ここでも印を立てるだけにする。
            Button("尺を合わせる") { store?.requestRefit() }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(store == nil)
            Button("全体を見る") { store?.requestWhole() }
                .keyboardShortcut("0", modifiers: [.shift, .command])
                .disabled(store == nil)
        }
        CommandMenu("移動") {
            Button("親へ") { store?.goToParent() }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(store?.selected == nil)

            Button("前の年へ") { if let s = store { s.setYear(s.year - 1) } }
                .keyboardShortcut(.leftArrow, modifiers: [.option, .command])
                .disabled(store == nil)
            Button("次の年へ") { if let s = store { s.setYear(s.year + 1) } }
                .keyboardShortcut(.rightArrow, modifiers: [.option, .command])
                .disabled(store == nil)
        }
    }
}
