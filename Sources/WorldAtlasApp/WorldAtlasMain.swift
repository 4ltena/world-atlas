import SwiftUI
import WorldAtlasUI

@main
struct WorldAtlasMain: App {
    var body: some Scene {
        // 先に書いたほうが起動時に出る。
        Window("vault を選ぶ", id: "vaults") {
            VaultListView()
        }
        .defaultSize(width: 520, height: 420)

        // 同じ URL には既にある窓が使われるので、同じ vault を二度開いても窓は増えない。
        WindowGroup(for: URL.self) { $url in
            if let url { VaultWindow(vault: url) }
        }
        .defaultSize(width: 1180, height: 760)
        .commands { AppCommands() }
    }
}
