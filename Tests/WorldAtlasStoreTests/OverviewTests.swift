import Foundation
import Testing
import WorldAtlasCore
@testable import WorldAtlasStore

@Suite("総観の読み取り")
struct OverviewTests {
    /// 一時ディレクトリを vault に見立てる。見本には触らない。
    private func makeVault() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("overview-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func write(_ vault: URL, year: Int, digest: String, text: String) throws {
        let dir = vault.appendingPathComponent(".atlas/overview", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let body = """
        ---
        model: qwen2.5:7b
        digest: \(digest)
        generated: 2026-09-08T12:00:00Z
        ---
        \(text)
        """
        try body.write(to: dir.appendingPathComponent("\(year).md"), atomically: true, encoding: .utf8)
    }

    @Test("要約値が一致すれば 生成済み")
    func ready() throws {
        let v = try makeVault()
        try write(v, year: 500, digest: "aaaa", text: "王家が絶えるまで一年。")
        let s = OverviewStore.state(vault: v, year: 500, digest: "aaaa", hasMaterial: true)
        guard case let .ready(doc) = s else { Issue.record("生成済みでない: \(s)"); return }
        #expect(doc.text == "王家が絶えるまで一年。")
        #expect(doc.model == "qwen2.5:7b")
    }

    @Test("要約値が食い違えば 古い。文は読めたまま出す")
    func stale() throws {
        let v = try makeVault()
        try write(v, year: 500, digest: "aaaa", text: "古い文。")
        let s = OverviewStore.state(vault: v, year: 500, digest: "bbbb", hasMaterial: true)
        guard case let .stale(doc) = s else { Issue.record("古いでない: \(s)"); return }
        #expect(doc.text == "古い文。")
    }

    @Test("ファイルが無ければ 未生成")
    func missing() throws {
        let v = try makeVault()
        #expect(OverviewStore.state(vault: v, year: 500, digest: "aaaa", hasMaterial: true) == .missing)
    }

    @Test("材料が無ければ 材料なし。ファイルの有無より先に決まる")
    func noMaterial() throws {
        let v = try makeVault()
        try write(v, year: 500, digest: "aaaa", text: "残っている文。")
        #expect(OverviewStore.state(vault: v, year: 500, digest: "aaaa", hasMaterial: false) == .noMaterial)
    }

    @Test("材料が無く、ファイルも無ければ 材料なし。未生成ではない")
    func noMaterialWithoutFile() throws {
        let v = try makeVault()
        #expect(OverviewStore.state(vault: v, year: 500, digest: "aaaa", hasMaterial: false) == .noMaterial)
    }

    @Test("front matter が壊れていても落ちない。未生成として扱う")
    func broken() throws {
        let v = try makeVault()
        let dir = v.appendingPathComponent(".atlas/overview", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "文だけがある".write(to: dir.appendingPathComponent("500.md"),
                             atomically: true, encoding: .utf8)
        #expect(OverviewStore.state(vault: v, year: 500, digest: "aaaa", hasMaterial: true) == .missing)
    }

    @Test("負の年もファイル名にできる")
    func negativeYear() throws {
        let v = try makeVault()
        try write(v, year: -12, digest: "aaaa", text: "世界の前。")
        guard case .ready = OverviewStore.state(vault: v, year: -12, digest: "aaaa", hasMaterial: true)
        else { Issue.record("読めていない"); return }
    }

    @Test("本文が複数行でも、front matter の後ろを丸ごと採る")
    func multiline() throws {
        let v = try makeVault()
        try write(v, year: 500, digest: "aaaa", text: "一行目。\n\n二行目。")
        guard case let .ready(doc) = OverviewStore.state(vault: v, year: 500, digest: "aaaa", hasMaterial: true)
        else { Issue.record("読めていない"); return }
        #expect(doc.text == "一行目。\n\n二行目。")
    }
}
