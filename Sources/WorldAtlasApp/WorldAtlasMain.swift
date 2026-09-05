import SwiftUI
import WorldAtlasCore
import WorldAtlasUI

@main
struct WorldAtlasMain: App {
    var body: some Scene {
        // 課題 11 で vault の一覧の窓と vault の窓に置き換える。
        // ここではレールのアイコンが並ぶだけの窓を出し、.app の組み立てを確かめる。
        WindowGroup("world-atlas") {
            VStack(spacing: 16) {
                ForEach(Kind.allCases, id: \.self) { k in
                    KindIcon(kind: k)
                        .stroke(lineWidth: 1.5)
                        .frame(width: 24, height: 24)
                }
            }
            .padding(24)
        }
    }
}
