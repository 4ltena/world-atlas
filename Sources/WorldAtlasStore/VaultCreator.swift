import Foundation
import WorldAtlasCore

/// 空でないディレクトリでも vault にできる。無いものだけを作り、既にあるファイルには
/// 触らない。世界.yaml が既にあるときだけ、既存の vault なので断る（設計書 4.1）。
public enum VaultCreator {
    public struct Failure: Error, Equatable, Sendable {
        public var message: String
    }

    public static func create(at dir: URL, worldName: String, calendarName: String) throws {
        let worldFile = dir.appendingPathComponent("世界.yaml")
        if FileManager.default.fileExists(atPath: worldFile.path) {
            throw Failure(message: "このディレクトリには既に 世界.yaml があります。開くほうを選んでください。")
        }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for k in Kind.allCases {
            try FileManager.default.createDirectory(at: dir.appendingPathComponent(k.rawValue),
                                                    withIntermediateDirectories: true)
        }
        // 暦は基準暦の一つだけで始める。増やすのは 世界.yaml を手で書き換える。
        let world = World(name: worldName, baseCalendar: calendarName,
                          calendars: [CalendarDef(name: calendarName, offset: 0)], current: 1)
        try WorldFile.render(world).write(to: worldFile, atomically: true, encoding: .utf8)
    }
}
