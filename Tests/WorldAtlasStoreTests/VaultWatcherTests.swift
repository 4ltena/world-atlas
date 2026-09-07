import Foundation
import Testing
import WorldAtlasCore
@testable import WorldAtlasStore

@Suite struct VaultWatcherTests {
    @Test func reportsChangedMarkdownFiles() async throws {
        let vault = try SampleVault.copy()
        let received = Box<[URL]>([])
        let watcher = VaultWatcher(vault: vault) { urls in received.update { $0 += urls } }
        try watcher.start()
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(500))
        let file = vault.appendingPathComponent("場所/川向こう.md")
        try (try String(contentsOf: file, encoding: .utf8) + "\n追記\n").write(to: file, atomically: true, encoding: .utf8)
        try await waitUntil(timeout: 5) { received.value.contains { $0.lastPathComponent == "川向こう.md" } }
    }

    @Test func ignoresDotAtlasAndItsCreation() async throws {
        let vault = try SampleVault.copy()
        let received = Box<[URL]>([])
        let watcher = VaultWatcher(vault: vault) { urls in received.update { $0 += urls } }
        try watcher.start()
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(500))
        let dir = vault.appendingPathComponent(".atlas")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "x".write(to: dir.appendingPathComponent("state.json"), atomically: true, encoding: .utf8)
        try await Task.sleep(for: .seconds(1))
        // .atlas 配下（ディレクトリ自体と中の state.json）が報告に含まれないことだけを検査する。
        // SampleVault.copy() 直後は世界.md/世界.yaml 等のコピー由来イベントが遅れて届くことがあり、
        // 「何も届かない」という主張はこのテストの本来の要求より強すぎる。
        #expect(!received.value.contains { $0.path.contains("/.atlas") })
    }

    @Test func externalEditReachesTheSnapshot() async throws {
        let vault = try SampleVault.copy()
        let indexer = try Indexer(vault: vault)
        _ = try await indexer.rebuild()
        let latest = Box<Snapshot?>(nil)
        try await indexer.startWatching { s in latest.update { $0 = s } }
        try await Task.sleep(for: .milliseconds(500))
        let file = vault.appendingPathComponent("場所/川向こう.md")
        try "---\n名前: 川向こう\n種別: 区\n期間: [520, 現在]\n親: エルデン邑\n---\n[[石橋]]を見る。\n".write(to: file, atomically: true, encoding: .utf8)
        try await waitUntil(timeout: 5) { latest.value?.refs["場所/川向こう.md"] == ["場所/石橋.md"] }
        await indexer.stopWatching()
    }

    // C1: 消したファイルの実体パスは、消えた時点で標準化しても /private が剥がれないため、
    // vault の名前空間へ戻さずに reindex へ渡すと相対化がずれて削除が索引に反映されない。
    // ここは削除と、それを指していた refs/backrefs の消滅を、監視の経路そのもので確かめる。
    @Test func deletionReachesTheSnapshotThroughTheWatcher() async throws {
        let vault = try SampleVault.copy()
        let indexer = try Indexer(vault: vault)
        _ = try await indexer.rebuild()
        let latest = Box<Snapshot?>(nil)
        try await indexer.startWatching { s in latest.update { $0 = s } }
        try await Task.sleep(for: .milliseconds(500))
        let file = vault.appendingPathComponent("場所/川向こう.md")
        try FileManager.default.removeItem(at: file)
        try await waitUntil(timeout: 5) {
            guard let s = latest.value else { return false }
            return s.nodes["場所/川向こう.md"] == nil && s.refs["場所/エルデン邑.md"]?.contains("場所/川向こう.md") != true
        }
        await indexer.stopWatching()
        let s = try #require(latest.value)
        #expect(s.nodes["場所/川向こう.md"] == nil)
        #expect(s.backrefs["場所/川向こう.md"] == nil)
    }

    // **止めたあとに書く。**もとは書いてから止めており、FSEvents の遅延（既定 0.3 秒）
    // より先に停止が済むことを当てにしていた——並行して走る試験の負荷が高いと崩れる。
    // 加えて、もとの形は `calls.value == 0` だけを見ていたので、**`startWatching` が
    // まったく効いていなくても通った。**先に効いていることを確かめてから止める。
    @Test func stopWatchingStopsFurtherUpdates() async throws {
        let vault = try SampleVault.copy()
        let indexer = try Indexer(vault: vault)
        _ = try await indexer.rebuild()
        let calls = Box<Int>(0)
        try await indexer.startWatching { _ in calls.update { $0 += 1 } }
        try await Task.sleep(for: .milliseconds(500))
        let file = vault.appendingPathComponent("場所/川向こう.md")

        // 監視が効いていることを確かめる。
        try (try String(contentsOf: file, encoding: .utf8) + "\n追記\n").write(to: file, atomically: true, encoding: .utf8)
        let deadline = ContinuousClock.now + .seconds(5)
        while calls.value == 0, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(50)) }
        try #require(calls.value > 0, "止める前に監視が効いていない")

        await indexer.stopWatching()
        let before = calls.value
        try (try String(contentsOf: file, encoding: .utf8) + "\nさらに追記\n").write(to: file, atomically: true, encoding: .utf8)
        try await Task.sleep(for: .seconds(2))
        #expect(calls.value == before)      // 止めたあとは増えない
    }
}

@Suite struct VaultWatcherPathClassificationTests {
    // M1: FSEvents に何も投げず、判定だけを純粋な関数として決定的に検査する。存在するかどうか
    // を一切見ないことが要点で、最後のケース（消えたファイルのパス）が C1 の再発を止める。
    @Test func mapsRawPathsToTheOriginalVaultNamespace() {
        let vault = URL(fileURLWithPath: "/var/folders/xx/T/haikai-test")
        let resolved = "/private/var/folders/xx/T/haikai-test"
        func classify(_ raw: String) -> URL? {
            VaultWatcher.mapToVaultNamespace(resolvedVault: resolved, vault: vault, rawPath: raw)
        }
        #expect(classify(resolved + "/.atlas") == nil)
        #expect(classify(resolved + "/.atlas/state.json") == nil)
        #expect(classify(resolved) == nil)
        #expect(classify(resolved + "/世界.yaml") == vault.appendingPathComponent("世界.yaml"))
        #expect(classify(resolved + "/場所/川向こう.md") == vault.appendingPathComponent("場所/川向こう.md"))
        // 消えたファイルのパス。ディスク上に存在しなくても、実装は存在チェックをしないので
        // 他の通常ファイルと同じく vault の名前空間へ戻る。
        #expect(classify(resolved + "/場所/消えた.md") == vault.appendingPathComponent("場所/消えた.md"))
    }
}

final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var v: T
    init(_ v: T) { self.v = v }
    var value: T { lock.withLock { v } }
    func update(_ f: (inout T) -> Void) { lock.withLock { f(&v) } }
}

func waitUntil(timeout: TimeInterval, _ cond: @escaping @Sendable () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if cond() { return }
        try await Task.sleep(for: .milliseconds(50))
    }
    Issue.record("時間内に条件を満たさなかった")
}
