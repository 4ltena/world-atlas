import SwiftUI

/// この段で動く操作だけをメニューに置く（設計書 8.1）。
/// 年表 ⌥⌘T はStage 3、保存 ⌘S と新規項目 ⌘N はStage 4、右の欄 ⌥⌘I はStage 5、
/// 設定 ⌘, はStage 6 で足す。
public struct AppCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.vaultStore) private var store

    public init() {}

    public var body: some Commands {
        CommandGroup(replacing: .newItem) {
            // 開くのも新規作成も一覧の窓から行うので、ここはその窓を前に出すだけである。
            // フォルダ選択を直接出す道は持たない（設計書 4.1、8.1）。
            Button("vault の一覧") { openWindow(id: "vaults") }
                .keyboardShortcut("o", modifiers: .command)
        }
        CommandMenu("表示") {
            Button(store?.showsRawEffectively == true ? "表示に切り替える" : "原文に切り替える") {
                store?.showsRaw.toggle()
            }
            .keyboardShortcut("e", modifiers: [.option, .command])
            // 壊れた節点は原文だけが使えるので、切り替えられない（設計書 4.4）。
            .disabled(store == nil || store?.isBroken == true)
        }
        CommandMenu("移動") {
            Button("親へ") { store?.goToParent() }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(store?.selected == nil)
        }
    }
}
