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
        #expect(received.value.isEmpty)
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
