import Foundation
import Testing
import WorldAtlasCore

@Suite struct SampleVaultTests {
    @Test func everyFileParses() throws {
        var count = 0
        for kind in Kind.allCases {
            let dir = SampleVault.url.appendingPathComponent(kind.rawValue)
            let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".md") }
            for f in files {
                let text = try String(contentsOf: dir.appendingPathComponent(f), encoding: .utf8)
                let node = try FrontMatter.parse(text, kind: kind)
                #expect(node.name + ".md" == f, "ファイル名と保存名が違う: \(f)")
                count += 1
            }
        }
        #expect(count == 66)
    }

    @Test func worldFileParses() throws {
        let w = try WorldFile.parse(String(contentsOf: SampleVault.url.appendingPathComponent("世界.yaml"), encoding: .utf8))
        #expect(w.name == "灰海")
        #expect(w.current == 500)
    }
}
