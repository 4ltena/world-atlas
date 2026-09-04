import Foundation
import GRDB
import WorldAtlasCore

public struct IndexerError: Error, Sendable {
    public var message: String
}

/// vault を走査して索引を作り、snapshot を出す。DB の接続はここにだけある。
public actor Indexer {
    public let vault: URL
    private let queue: DatabaseQueue
    public private(set) var snapshot: Snapshot = .empty
    private var watcher: VaultWatcher?
    // startWatching のたびに増やす。停止・再開のまたぎで、以前の watcher が積んだ
    // Task が actor へ戻ってきても、この世代がずれていれば古い呼び出しとして捨てる。
    private var watchGeneration = 0

    public init(vault: URL) throws {
        self.vault = vault
        self.queue = try IndexDatabase.open(vault: vault)
    }

    // MARK: 走査

    /// 全走査。索引を空にしてから入れ直す。
    public func rebuild() throws -> Snapshot {
        // 消す前に読む。世界.yaml が壊れているときに索引を空にして終わらないため。
        let world = try readWorld()
        var ignored = 0
        var files: [URL] = []
        let entries = try FileManager.default.contentsOfDirectory(at: vault, includingPropertiesForKeys: [.isDirectoryKey])
        for e in entries {
            guard (try? e.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            if e.lastPathComponent.hasPrefix(".") { continue }
            guard Kind(rawValue: e.lastPathComponent) != nil else { ignored += 1; continue }
            // 型のディレクトリの下は再帰で辿る。入れ子は木の親子を表さないが、置かれた
            // ファイルを落とす理由も無い。. で始まるものは飛ばす。
            let inner = FileManager.default.enumerator(at: e, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            files += (inner?.compactMap { $0 as? URL } ?? []).filter { $0.pathExtension == "md" }
        }
        try queue.write { db in
            for t in ["node", "alias", "mark", "rule", "lineage", "ref", "calendar"] {
                try db.execute(sql: "DELETE FROM \(t)")
            }
        }
        try writeCalendars(world)
        for f in files { try upsert(f) }
        snapshot = try buildSnapshot(world: world, ignored: ignored)
        return snapshot
    }

    /// 指定したファイルだけを索引し直す。消えていれば行を消す。世界.yaml なら暦を入れ直す。
    public func reindex(_ files: [URL]) throws -> Snapshot {
        var world = snapshot.world
        for f in files {
            if f.lastPathComponent == "世界.yaml" {
                world = try readWorld()
                try writeCalendars(world)
                continue
            }
            guard f.pathExtension == "md", Kind(rawValue: kindDirectory(of: f)) != nil else { continue }
            if FileManager.default.fileExists(atPath: f.path) {
                try upsert(f)
            } else {
                let rel = relativePath(of: f)
                try queue.write { db in try deleteRows(path: rel, db: db) }
            }
        }
        snapshot = try buildSnapshot(world: world, ignored: snapshot.ignoredDirectories)
        return snapshot
    }

    /// 節点の本文。UTF-8 で読めないファイルはここで throw する（段 4 が扱い方を決める）。
    /// 壊れた節点は原文だけが直す手がかりなので、front matter を落とさず全文を返す（設計書 4.4）。
    public func body(of path: String) throws -> String {
        let text = try String(contentsOf: fileURL(of: path), encoding: .utf8)
        if snapshot.nodes[path]?.flags.contains(.broken) == true { return text }
        return FrontMatter.split(text)?.body ?? text
    }

    public func fileURL(of path: String) -> URL {
        vault.appendingPathComponent(path)
    }

    // MARK: 監視

    /// vault を見張り、変わったファイルを索引し直して onUpdate に新しい snapshot を渡す。
    public func startWatching(onUpdate: @escaping @Sendable (Snapshot) -> Void) throws {
        guard watcher == nil else { return }
        watchGeneration += 1
        let generation = watchGeneration
        let w = VaultWatcher(vault: vault) { [weak self] urls in
            guard let self else { return }
            Task {
                await self.reindexAndNotifyIfCurrent(urls, generation: generation, onUpdate: onUpdate)
            }
        }
        try w.start()
        watcher = w
    }

    public func stopWatching() {
        watcher?.stop()
        watcher = nil
    }

    /// generation が今の世代と合い、まだ監視中の時だけ reindex し、そのまま同じ隔離区間の
    /// 中で onUpdate を呼ぶ。確認（世代・監視中か）から通知までを分けずに actor の中で
    /// 続けて行うことで、その間に stopWatching が割り込んで古い通知が漏れることを防ぐ。
    private func reindexAndNotifyIfCurrent(_ files: [URL], generation: Int, onUpdate: @Sendable (Snapshot) -> Void) {
        guard watcher != nil, generation == watchGeneration else { return }
        guard let s = try? reindex(files) else { return }
        onUpdate(s)
    }

    // MARK: 内部

    private func readWorld() throws -> World {
        let text = try String(contentsOf: vault.appendingPathComponent("世界.yaml"), encoding: .utf8)
        return try WorldFile.parse(text)
    }

    private func writeCalendars(_ world: World) throws {
        try queue.write { db in
            try db.execute(sql: "DELETE FROM calendar")
            for c in world.calendars {
                try db.execute(sql: "INSERT INTO calendar(name, offset) VALUES (?, ?)", arguments: [c.name, c.offset])
            }
        }
    }

    private func relativePath(of url: URL) -> String {
        let base = vault.standardizedFileURL.path
        let p = url.standardizedFileURL.path
        return p.hasPrefix(base + "/") ? String(p.dropFirst(base.count + 1)) : p
    }

    private func kindDirectory(of url: URL) -> String {
        relativePath(of: url).split(separator: "/").first.map(String.init) ?? ""
    }

    /// 一ファイルを読み、その path の行を入れ直す。壊れていれば broken の行だけ入れる。
    private func upsert(_ file: URL) throws {
        let rel = relativePath(of: file)
        guard let kind = Kind(rawValue: kindDirectory(of: file)) else { return }
        let stem = file.deletingPathExtension().lastPathComponent
        let mtime = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate?.timeIntervalSince1970) ?? 0
        try queue.write { db in
            try deleteRows(path: rel, db: db)
            let node: Node
            do {
                // 読み込みもこの中で行う。UTF-8 で読めない一ファイルが走査全体を止めないため。
                node = try FrontMatter.parse(String(contentsOf: file, encoding: .utf8), kind: kind)
            } catch {
                try db.execute(sql: """
                    INSERT INTO node(path, name, kind, category, "from", "to", isPoint, parent, mtime, broken, mismatch)
                    VALUES (?, ?, ?, '', 0, NULL, 0, NULL, ?, 1, 0)
                    """, arguments: [rel, stem, kind.rawValue, mtime])
                return
            }
            try db.execute(sql: """
                INSERT INTO node(path, name, kind, category, "from", "to", isPoint, parent, mtime, broken, mismatch)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?)
                """, arguments: [rel, node.name, kind.rawValue, node.category, node.from, node.to, node.isPoint, node.parent, mtime, node.name != stem])
            for a in node.aliases {
                try db.execute(sql: "INSERT INTO alias(node, \"from\", name) VALUES (?, ?, ?)", arguments: [rel, a.from, a.name])
            }
            for m in node.marks {
                try db.execute(sql: "INSERT INTO mark(node, year, label) VALUES (?, ?, ?)", arguments: [rel, m.year, m.label])
            }
            for r in node.rules {
                try db.execute(sql: "INSERT INTO rule(node, \"from\", \"to\", polity) VALUES (?, ?, ?, ?)", arguments: [rel, r.from, r.to, r.polity])
            }
            for l in node.lineages {
                try db.execute(sql: "INSERT INTO lineage(node, year, kind, origin) VALUES (?, ?, ?, ?)", arguments: [rel, l.year, l.kind, l.origin])
            }
            for c in WikiLinks.counts(in: node.body) {
                try db.execute(sql: "INSERT INTO ref(source, target, count) VALUES (?, ?, ?)", arguments: [rel, c.target, c.count])
            }
        }
    }

    /// path に紐づく行をすべて消す。
    private func deleteRows(path: String, db: Database) throws {
        for t in ["alias", "mark", "rule", "lineage"] {
            try db.execute(sql: "DELETE FROM \(t) WHERE node = ?", arguments: [path])
        }
        try db.execute(sql: "DELETE FROM ref WHERE source = ?", arguments: [path])
        try db.execute(sql: "DELETE FROM node WHERE path = ?", arguments: [path])
    }

    private func buildSnapshot(world: World, ignored: Int) throws -> Snapshot {
        var nodes: [String: IndexedNode] = [:]
        var names: [String: [String]] = [:]
        var savedNames: [String: [String]] = [:]
        var rawRefs: [(source: String, target: String)] = []
        try queue.read { db in
            var aliases: [String: [Alias]] = [:]
            for r in try Row.fetchAll(db, sql: "SELECT node, \"from\", name FROM alias ORDER BY rowid") {
                aliases[r["node"], default: []].append(Alias(from: r["from"], name: r["name"]))
            }
            var marks: [String: [Mark]] = [:]
            for r in try Row.fetchAll(db, sql: "SELECT node, year, label FROM mark ORDER BY rowid") {
                marks[r["node"], default: []].append(Mark(year: r["year"], label: r["label"]))
            }
            var rules: [String: [Rule]] = [:]
            for r in try Row.fetchAll(db, sql: "SELECT node, \"from\", \"to\", polity FROM rule ORDER BY rowid") {
                rules[r["node"], default: []].append(Rule(from: r["from"], to: r["to"], polity: r["polity"]))
            }
            var lineages: [String: [Lineage]] = [:]
            for r in try Row.fetchAll(db, sql: "SELECT node, year, kind, origin FROM lineage ORDER BY rowid") {
                lineages[r["node"], default: []].append(Lineage(year: r["year"], kind: r["kind"], origin: r["origin"]))
            }
            for r in try Row.fetchAll(db, sql: "SELECT * FROM node") {
                let path: String = r["path"]
                var flags = Set<Flag>()
                if r["broken"] as Bool { flags.insert(.broken) }
                if r["mismatch"] as Bool { flags.insert(.nameMismatch) }
                let n = IndexedNode(
                    path: path, name: r["name"], kind: Kind(rawValue: r["kind"])!, category: r["category"],
                    from: r["from"], to: r["to"], isPoint: r["isPoint"], parent: r["parent"], parentPath: nil,
                    aliases: aliases[path] ?? [], rules: rules[path] ?? [], lineages: lineages[path] ?? [],
                    marks: marks[path] ?? [], flags: flags
                )
                nodes[path] = n
                // 壊れた行の name は stem であり、名前の一覧には載せない。
                if !flags.contains(.broken) {
                    savedNames[n.name, default: []].append(path)
                    names[n.name, default: []].append(path)
                    for a in n.aliases { names[a.name, default: []].append(path) }
                }
            }
            for r in try Row.fetchAll(db, sql: "SELECT source, target FROM ref ORDER BY rowid") {
                rawRefs.append((r["source"], r["target"]))
            }
        }
        // 同じ path が同じ名前を二度持つ（保存名と別名が同じ等）ことはあるので、path を重複なく数える。
        for (k, v) in names { names[k] = v.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } } }
        // 重複の印。保存名が二つ以上の path に付いている節点。別名の衝突では付かない。
        for (path, n) in nodes where (savedNames[n.name]?.count ?? 0) > 1 && !n.flags.contains(.broken) {
            nodes[path]!.flags.insert(.duplicate)
        }
        // 親の解決。保存名で、同じ型で、一意に見つかったときだけ繋ぐ。
        for (path, n) in nodes {
            if let p = n.parent, let ps = savedNames[p], ps.count == 1, let parent = nodes[ps[0]], parent.kind == n.kind, ps[0] != path {
                nodes[path]!.parentPath = ps[0]
            }
        }
        // 親の輪を切る。輪の節点はどれも parentPath を持つので roots に入らず、互いの
        // children にしか現れないため木から永久に見えなくなる。輪を閉じる一辺だけを
        // nil にすると、その節点が根になり残りはその子として辿れる。印は付けない。
        for start in nodes.keys {
            var seen: Set<String> = [start]
            var cur = start
            while let next = nodes[cur]!.parentPath {
                if !seen.insert(next).inserted { nodes[cur]!.parentPath = nil; break }
                cur = next
            }
        }
        // 参照の解決。
        var refs: [String: [String]] = [:]
        var backrefs: [String: [String]] = [:]
        var unresolved: [String: [String]] = [:]
        for (source, raw) in rawRefs {
            if let ps = names[raw], ps.count == 1, ps[0] != source {
                if refs[source]?.contains(ps[0]) != true { refs[source, default: []].append(ps[0]) }
                backrefs[ps[0], default: []].append(source)
            } else if names[raw]?.count != 1 {
                unresolved[source, default: []].append(raw)
            }
        }
        for k in backrefs.keys { backrefs[k]!.sort { (nodes[$0]?.name ?? $0) < (nodes[$1]?.name ?? $1) } }
        // 木。開始年、同年は名前。
        var children: [String: [String]] = [:]
        var roots: [Kind: [String]] = [:]
        let ordered = nodes.values.sorted { a, b in a.from != b.from ? a.from < b.from : a.name < b.name }
        for n in ordered {
            if let p = n.parentPath { children[p, default: []].append(n.path) } else { roots[n.kind, default: []].append(n.path) }
        }
        let extent = Extent.compute(nodes: nodes.values.filter { !$0.flags.contains(.broken) }.map(\.asNode), current: world.current)
        return Snapshot(world: world, nodes: nodes, names: names, savedNames: savedNames, children: children,
                        roots: roots, refs: refs, backrefs: backrefs, unresolved: unresolved,
                        extent: extent, ignoredDirectories: ignored)
    }
}
