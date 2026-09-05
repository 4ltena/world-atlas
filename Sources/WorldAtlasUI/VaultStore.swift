import Foundation
import Observation
import WorldAtlasCore
import WorldAtlasStore

/// 一つの窓が持つ状態。索引の actor から画面へ渡す道はここ一本だけである。
@MainActor
@Observable
public final class VaultStore {
    public let vault: URL

    public private(set) var snapshot: Snapshot = .empty
    /// vault を開けなかった理由。窓はこれを出して何もしない。
    public private(set) var loadError: String?
    /// 開いている節点の path。nil なら世界全体の概要（世界.md）を出す。
    public private(set) var selected: String?
    /// 表示している本文。front matter は落としてある。selected が nil なら 世界.md の本文。
    public private(set) var text: String = ""
    /// 原文の欄に出す全文。front matter を含む。Stage 2 では読むだけである。
    public private(set) var raw: String = ""
    /// 本文を読めなかった理由。
    public private(set) var textError: String?

    public var kind: Kind = .place
    public var year: Int = 1
    public var calendarName: String = ""
    public var expanded: Set<String> = []
    /// 利用者が選んだ区分け。壊れた節点では下の showsRawEffectively が優先する。
    public var showsRaw = false
    public var query: String = "" {
        didSet {
            guard query != oldValue else { return }
            // 絞り込んだら、当たった行まで開いておく。
            if !query.trimmingCharacters(in: .whitespaces).isEmpty { expanded.formUnion(Tree.branches(rows)) }
        }
    }

    private var indexer: Indexer?
    // 本文の読み込みが前後しても、最後に頼んだものだけを採る。頼む側が同期のうちに
    // 増やし、そのときの値と対象を reloadText へ渡す。
    private var textToken = 0

    public init(vault: URL) { self.vault = vault }

    // MARK: 画面が読むもの

    public var calendar: CalendarDef {
        snapshot.world.calendars.first { $0.name == calendarName }
            ?? CalendarDef(name: snapshot.world.baseCalendar, offset: 0)
    }

    /// 66 件ほどの vault を前提に、その都度組み直す（設計書 15 節、千を超える規模は対象外）。
    public var rows: [TreeNode] { Tree.build(snapshot, kind: kind, year: year, query: query) }

    public var header: Header? {
        selected.flatMap { Manuscript.header(snapshot, path: $0, year: year, calendar: calendar) }
    }

    public var blocks: [RenderedBlock] { BodyRenderer.render(text, snapshot: snapshot, year: year) }

    /// 開いている節点が壊れているか。
    public var isBroken: Bool {
        selected.flatMap { snapshot.nodes[$0]?.flags.contains(.broken) } ?? false
    }

    /// 実際に原文を出すか。壊れた節点は原文だけが使えるので、選んだ区分けに関わらず原文である
    /// （設計書 4.4）。front matter が YAML として読めない以上、表示に出せる本文が無い。
    public var showsRawEffectively: Bool { isBroken || showsRaw }

    // MARK: 動かすもの

    public func load() async {
        do {
            let ix = try Indexer(vault: vault)
            indexer = ix
            let s = try await ix.rebuild()
            snapshot = s
            calendarName = s.world.baseCalendar
            year = s.world.current
            // 覚えていた節点が消えていたら、黙って既定へ戻す（設計書 11 節）。
            let remembered = VaultState.read(vault: vault).openNode
            selected = remembered.flatMap { s.nodes[$0] != nil ? $0 : nil }
            if let p = selected { kind = s.nodes[p]!.kind; reveal(p) }
            textToken += 1
            await reloadText(token: textToken, target: selected)
            try await ix.startWatching { [weak self] snap in
                Task { @MainActor in self?.apply(snap) }
            }
        } catch {
            loadError = describe(error)
        }
    }

    public func select(_ path: String?) {
        guard path != selected else { return }
        if let path {
            guard let n = snapshot.nodes[path] else { return }
            kind = n.kind
            reveal(path)
        }
        selected = path
        VaultState.write(VaultState(openNode: path), vault: vault)
        // 選んだその場で古い読み込みを無効にする。予約した task が走り始めるのを
        // 待つと、その隙に前の読み込みが再開して古い本文を書けてしまう。
        textToken += 1
        let token = textToken
        Task { await reloadText(token: token, target: path) }
    }

    public func goToParent() {
        guard let p = selected, let pp = snapshot.nodes[p]?.parentPath else { return }
        select(pp)
    }

    public func stop() async {
        await indexer?.stopWatching()
    }

    // MARK: 内部

    private func apply(_ s: Snapshot) {
        snapshot = s
        // 開いていた節点が消えたら、概要へ戻す。
        if let p = selected, s.nodes[p] == nil { selected = nil }
        textToken += 1
        let token = textToken
        let target = selected
        Task { await reloadText(token: token, target: target) }
    }

    /// path が木の中で見えるように、祖先をすべて開く。
    private func reveal(_ path: String) {
        var cur = snapshot.nodes[path]?.parentPath
        var guardSet: Set<String> = [path]
        while let c = cur, guardSet.insert(c).inserted {
            expanded.insert(c)
            cur = snapshot.nodes[c]?.parentPath
        }
    }

    /// token が最新のままの時だけ書き込む。頼まれた対象を一緒に受け取るので、
    /// 待っているあいだに選択が変わっても、この読み込みは頼まれたものを読み続ける。
    private func reloadText(token: Int, target: String?) async {
        var loaded = ""
        var whole = ""
        var failure: String?
        if let target, let ix = indexer {
            // 表示は body（front matter を落としたもの）、原文は全文。壊れた節点では
            // body も全文を返すので、二つは同じになる。
            let url = await ix.fileURL(of: target)
            do {
                loaded = try await ix.body(of: target)
                whole = try String(contentsOf: url, encoding: .utf8)
            } catch {
                failure = "このファイルは UTF-8 として読めません。"
            }
        } else if target == nil {
            loaded = (try? String(contentsOf: vault.appendingPathComponent("世界.md"), encoding: .utf8)) ?? ""
            whole = loaded
        }
        guard token == textToken else { return }
        text = loaded
        raw = whole
        textError = failure
    }

    private func describe(_ error: Error) -> String {
        if let e = error as? FrontMatterError {
            return e.line.map { "世界.yaml の \($0) 行目: \(e.message)" } ?? "世界.yaml: \(e.message)"
        }
        if let e = error as? IndexerError { return e.message }
        return "\(error)"
    }
}
