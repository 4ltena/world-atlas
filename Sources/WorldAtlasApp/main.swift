// 段 2 で SwiftUI の App に置き換える。この段では vault を走査して数を出すだけ。
import Foundation
import WorldAtlasCore
import WorldAtlasStore

// 端末以外へ繋いだときも行ごとに流す。--watch の出力をファイルやパイプで見るため。
setvbuf(stdout, nil, _IOLBF, 0)

func printErr(_ s: String) {
    FileHandle.standardError.write((s + "\n").data(using: .utf8)!)
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("使い方: WorldAtlasApp <vault のパス>")
    exit(2)
}
let vaultPath = args[1]
var isDirectory: ObjCBool = false
guard FileManager.default.fileExists(atPath: vaultPath, isDirectory: &isDirectory), isDirectory.boolValue else {
    printErr("vault が見つかりません: \(vaultPath)")
    exit(1)
}

@Sendable func report(_ s: Snapshot) {
    print("\(s.world.name): \(s.nodes.count) 件、\(s.extent.lo)–\(s.extent.hi) 年、未解決のリンク \(s.unresolved.values.map(\.count).reduce(0, +)) 件")
}

do {
    let indexer = try Indexer(vault: URL(fileURLWithPath: vaultPath))
    report(try await indexer.rebuild())
    if args.count >= 3, args[2] == "--watch" {
        try await indexer.startWatching { s in report(s) }
        print("監視中。Ctrl-C で終わる。")
        while true { try await Task.sleep(for: .seconds(60)) }
    }
} catch {
    printErr("vault を読めません: \(vaultPath)\n\(error)")
    exit(1)
}
