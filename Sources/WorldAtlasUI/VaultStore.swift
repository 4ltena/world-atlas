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
            recordRecent(s)
            year = s.world.current
            // 覚えていた暦と節点は同じファイルから読む。VaultState.read を二度呼ばない。
            let remembered = VaultState.read(vault: vault)
            calendarName = remembered.calendar.flatMap { name in
                s.world.calendars.contains { $0.name == name } ? name : nil
            } ?? s.world.baseCalendar
            // 覚えていた節点が消えていたら、黙って既定へ戻す（設計書 11 節）。
            selected = remembered.openNode.flatMap { s.nodes[$0] != nil ? $0 : nil }
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
        var st = VaultState.read(vault: vault)
        st.openNode = path
        VaultState.write(st, vault: vault)
        // 節点を選び直したら表示中の行に合わせる（設計書 8.6）。幅は View が持っている
        // ので、ここでは印だけ立てる。
        requestRefit()
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

    // MARK: 年表（設計書 8.5、8.6、11 節）

    /// 年を動かしてからファイルへ書き戻すまでの間（設計書 4.2）。試験のためだけに縮める。
    nonisolated(unsafe) static var writeDelay: Duration = .seconds(1)

    /// 表示している年の範囲。幅が決まるまで nil。
    public private(set) var scale: TimelineTransform?

    /// 年カーソルを掴んでいるあいだの年。**読みと線だけがこれに追随し、木と本文は動かない**
    /// （設計書 8.6「動かしている間は年の読みだけが追随し、離した時点で呼び名が切り替わる」）。
    /// 離すときに `setYear` を呼んで nil へ戻す。
    public var draggingYear: Int?
    /// 年の読みと年カーソルの線が使う年。木・本文・年表の行は `year` のほうを見る。
    public var displayedYear: Int { draggingYear ?? year }
    /// 年表の高さの覚え。持ち主は VSplitView で、これは畳んで開き直すときに渡す控えである
    /// （TimelineView が実測した値を書き戻す）。**アプリ全体の値**なので、vault ごとの
    /// state.json ではなく UserDefaults に置く（設計書 11 節の @AppStorage の欄）。
    /// VaultStore は View ではないので @AppStorage は使えず、鍵を直に読み書きする。
    nonisolated static let timelineHeightKey = "timelineHeight"
    public private(set) var timelineHeight: Double = {
        let v = UserDefaults.standard.double(forKey: VaultStore.timelineHeightKey)
        return v > 0 ? v : 180
    }()
    public var timelineCollapsed = false
    public var showsRuleStripes = true

    public var timelineRows: [TimelineRow] {
        Timeline.rows(snapshot, selected: selected, kind: kind, year: year)
    }
    public var polityIndices: [String: Int] { Timeline.polityIndices(snapshot) }

    private var yearWriteTask: Task<Void, Never>?
    private var scaleWriteTask: Task<Void, Never>?

    /// 境目を掴んで変わった高さを覚える。畳んで開き直すときと、次に開く窓がこの値で始まる。
    public func setTimelineHeight(_ h: Double) {
        guard h > 0, abs(h - timelineHeight) > 0.5 else { return }
        timelineHeight = h
        UserDefaults.standard.set(h, forKey: Self.timelineHeightKey)
    }

    /// 基準暦の定義。`WorldFile.parse` は基準暦が `暦` の一覧にあることを確かめているので、
    /// 読み込み後は必ず見つかる。索引の前だけ加算値 0 の代わりを返す。
    public var baseCalendar: CalendarDef {
        snapshot.world.calendars.first { $0.name == snapshot.world.baseCalendar }
            ?? CalendarDef(name: snapshot.world.baseCalendar, offset: 0)
    }

    /// 窓の副題（設計書 8.1 の `根 職人街｜264–760（世界の 65%）`）。
    /// 年表の根と、いま見えている範囲と、それが世界に占める割合を出す。
    /// 尺がまだ決まっていない（索引前）ときは根だけを出す。
    public var timelineSubtitle: String {
        let root = selected.flatMap { snapshot.nodes[$0]?.displayName(at: year) } ?? kind.rawValue
        guard let t = scale else { return "根 \(root)" }
        let lo = Int(t.origin.rounded()), hi = Int((t.origin + t.years).rounded())
        let e = snapshot.extent
        let worldYears = Double(e.hi + 10 - e.lo)
        let share = worldYears > 0 ? Int((t.years / worldYears * 100).rounded()) : 100
        return "根 \(root)｜\(calendar.short(lo))–\(calendar.short(hi))（世界の \(min(share, 100))%）"
    }

    /// 暦を選ぶ。vault ごとの値なので state.json へ入れる（設計書 11 節）。
    public func setCalendar(_ name: String) {
        guard snapshot.world.calendars.contains(where: { $0.name == name }) else { return }
        calendarName = name
        var st = VaultState.read(vault: vault)
        st.calendar = name
        VaultState.write(st, vault: vault)
    }

    /// 年を動かす。世界の端で止まり、少し経ってから 世界.yaml へ書き戻す。
    public func setYear(_ y: Int) {
        let e = snapshot.extent
        let clamped = min(max(y, e.lo), e.hi + 10)
        guard clamped != year else { return }
        year = clamped
        yearWriteTask?.cancel()
        yearWriteTask = Task { [weak self] in
            try? await Task.sleep(for: Self.writeDelay)
            guard !Task.isCancelled else { return }
            await self?.persistYear()
        }
    }

    /// 索引が済んでいるか。**尺を決める入口はすべてこれを見る。**
    /// 窓は `task` で読み込む前に一度組まれるので、`Snapshot.empty`（端が 1...2）の状態で
    /// 尺を決めうる経路が複数ある。一つでも素通りすると、幅が変わらないかぎり作り直す契機が
    /// 無く、読み込みが済んでも狂ったまま残る。`WorldFile.parse` は空の名前を拒むので、
    /// 名前が入っていることが索引の済んだ印になる。
    public var isLoaded: Bool { !snapshot.world.name.isEmpty }

    /// 幅が決まったら、覚えていた尺を今の幅へ当てはめる。無ければ世界の全体を出す。
    public func ensureScale(width: Double) {
        guard width > 0, isLoaded else { return }
        if var t = scale {
            guard t.width != width else { return }
            // 見えている年の範囲を保ったまま、幅だけ入れ替える。
            let span = t.years
            t.width = width
            t.pxPerYear = width / span
            scale = t.clampedToBounds(snapshot.extent)
            return
        }
        let saved = VaultState.read(vault: vault)
        if let lo = saved.visibleFrom, let hi = saved.visibleTo, hi > lo {
            // **`fitting` を使わない。**あれは 40 年未満を 40 年へ広げるので、
            // 寄せて閉じた尺が開き直すたびに広がってしまう。
            scale = .showing(lo...hi, width: width, limits: snapshot.extent)
        } else {
            scale = .whole(width: width, limits: snapshot.extent)
        }
    }

    /// 「合わせる」。いま出ている行の範囲へ尺を当てはめ直す（設計書 8.6）。
    /// 行が一つも無い型では世界の全体にする。**そのときも `setScale` を通す**——
    /// 直に代入すると保存の予約が走らず、その尺だけが覚えられない。
    public func fitScale(width: Double) {
        let rows = timelineRows
        guard !rows.isEmpty else { return showWholeWorld(width: width) }
        let lo = rows.map(\.from).min() ?? snapshot.extent.lo
        let hi = rows.map { $0.to ?? snapshot.extent.hi }.max() ?? snapshot.extent.hi
        setScale(.fitting(lo...max(hi, lo), width: width, limits: snapshot.extent))
    }

    /// 「全体」。
    public func showWholeWorld(width: Double) {
        setScale(.whole(width: width, limits: snapshot.extent))
    }

    /// ピンチと掴みからも呼ぶ。尺が変わるたびに少し経ってから覚える。
    /// **索引の前は受けない。**「合わせる」「全体」は読み込み中でも押せるので、
    /// ここを通さないと空の世界の端で尺が確定してしまう。
    public func setScale(_ t: TimelineTransform) {
        guard isLoaded else { return }
        scale = t
        scaleWriteTask?.cancel()
        scaleWriteTask = Task { [weak self] in
            try? await Task.sleep(for: Self.writeDelay)
            guard !Task.isCancelled else { return }
            await self?.persistScale()
        }
    }

    /// 幅を持たない側（年ゲージの行、メニュー、`select`）から尺を頼むための印。
    /// **幅を知っているのは TimelineView だけ**なので、こちらは印を立てるに留める。
    /// 年表を畳んでいる間に立った印は、次に出てきたときに片づけられる。
    ///
    /// **真偽値を二つ持たない。**「全体」の後に「合わせる」を押したら合わせるが勝つべきだが、
    /// 独立した二つの旗だと互いを取り消さず、消費する側の順番で勝ち負けが決まってしまう。
    /// 一つしか立たない形にすれば、後から立てたものが必ず前のものを消す。
    public enum ScaleRequest: Sendable, Equatable { case fit, whole }
    public private(set) var scaleRequest: ScaleRequest?

    /// 「合わせる」を頼む。節点を選び直したときにも立てる。
    public func requestRefit() { scaleRequest = .fit }
    /// 「全体」を頼む。
    public func requestWhole() { scaleRequest = .whole }
    public func clearScaleRequest() { scaleRequest = nil }

    private func persistYear() {
        guard snapshot.world.current != year, !snapshot.world.name.isEmpty else { return }
        var w = snapshot.world
        w.current = year
        // 書けなければ黙って諦める。覚え書きが一つ古いだけで、作業は続けられる。
        try? WorldFile.render(w).write(to: vault.appendingPathComponent("世界.yaml"),
                                       atomically: true, encoding: .utf8)
    }

    private func persistScale() {
        guard let t = scale else { return }
        var s = VaultState.read(vault: vault)
        s.visibleFrom = Int(t.origin.rounded())
        s.visibleTo = Int((t.origin + t.years).rounded())
        VaultState.write(s, vault: vault)
    }

    // MARK: 内部

    /// 一覧の三段目のための材料を書き戻す（設計書 4.1）。一覧の窓は索引しないので、
    /// ここで書いたものがそのまま出る。開いたことのない vault は二段のままになる。
    private func recordRecent(_ s: Snapshot) {
        let d = UserDefaults.standard
        let list = RecentVaults.decode(d.string(forKey: RecentVaults.storageKey) ?? "[]")
        let out = RecentVaults.record(list, path: vault.path, nodes: s.nodes.count,
                                      from: s.extent.lo, to: s.extent.hi)
        d.set(RecentVaults.encode(out), forKey: RecentVaults.storageKey)
    }

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
        // ここへ来るのは索引を作れなかった類（GRDB の DatabaseError など）。何が起きたかと
        // 確かめることは日本語で伝え、ライブラリからの理由はそのまま引用する。
        // GRDB は localizedDescription にも英語の説明を入れるので、地域化は期待できない。
        return "この vault の索引を作れませんでした。ディスクの空きと、このディレクトリへ書き込めるかを確かめてください。"
            + "\n\nシステムからの理由（英語のことがあります）: \(error.localizedDescription)"
    }
}
