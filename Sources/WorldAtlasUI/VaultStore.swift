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
    ///
    /// **呼び名は `displayedYear` で解く。**年カーソルを掴んでいる最中も追随する（設計書 8.6）。
    /// 掴んでいる間は据え置く案を先に採ったが、2026-09-06 の実機確認で、動かしながら
    /// 名前が変わるほうが読み取れると判った。`draggingYear` は年が実際に変わったときだけ
    /// 書き換わる（`TimelineView` が同じ値の代入を落とす）ので、組み直しは 1 年に一度である。
    public var rows: [TreeNode] { Tree.build(snapshot, kind: kind, year: displayedYear, query: query) }

    public var header: Header? {
        selected.flatMap { Manuscript.header(snapshot, path: $0, year: displayedYear, calendar: calendar) }
    }

    public var blocks: [RenderedBlock] { BodyRenderer.render(text, snapshot: snapshot, year: displayedYear) }

    // MARK: 探した名前と、その年へ移る（設計書 7 節、8.3）

    /// 利用者がどの名前で辿り着いたか。検索で打った語、押したリンクの語である。
    /// **選択と年からは復元できない**ので、状態として持つ（設計書 7 節）。
    public private(set) var arrivedAs: String?
    /// 三択を抜けてから届ける分。関門で待たされる間、行き先と一緒に控えておく。
    private var pendingArrivedAs: String?
    /// 「その年へ移る」を押す前の年。⟲ で戻す。**一往復だけで、履歴は作らない。**
    public private(set) var returnYear: Int?

    /// 原稿の見出しの下に出す一行。要らなければ nil。
    public var arrival: Arrival? {
        guard let p = selected else { return nil }
        return ArrivalNotice.make(snapshot, path: p, year: displayedYear,
                                  arrivedAs: arrivedAs, calendar: calendar)
    }

    /// 「その年へ移る」。**押したときだけ年が動く**（設計書 8.3）。
    public func goToArrivalYear() {
        guard let a = arrival else { return }
        let before = year
        setYear(a.year)
        // **動かなかったなら、前の戻り先を残す。**端で丸められて年が変わらなかっただけで、
        // 先に押して得た戻り先まで捨てると、元の年へ帰る手段が消える。
        // **意図して試験で覆っていない。**通常の経路では一度動くと食い違いが解けて
        // `arrival` が nil になり、二度目の呼び出しは上の guard で先に止まる——ここへ
        // 来るには、期間の真ん中が世界の外に出るような壊れた front matter（逆転した
        // 期間）を要る。そのための見本を試験に混ぜてまで守る一行ではない。
        guard year != before else { return }
        returnYear = before
    }

    /// 「⟲ 元の年へ移る」。
    public func returnToPreviousYear() {
        guard let y = returnYear else { return }
        returnYear = nil
        setYear(y)
    }

    // MARK: 右の欄（設計書 8.4、9 節）

    /// 右の欄を出しているか。⌥⌘I で切り替える。
    public var showsInspector = true
    /// 下半分に出しているもの。**窓の中では覚えるが、state.json には入れない**
    /// （設計書 8.4）。次の起動は「この年のできごと」から始まる。
    public enum InspectorTab: Sendable, Equatable { case events, relations }
    public var inspectorTab: InspectorTab = .events

    /// 総観の材料。前後 12 年（設計書 9 節）。
    public var facts: [Fact] {
        Facts.around(year: displayedYear, window: 12,
                     sources: snapshot.nodes.map { FactSource(path: $0.key, node: $0.value.asNode) })
    }

    /// 総観の状態。**生成はしない**（Stage 6）。読んで、今の材料と比べるだけである。
    public var overviewState: OverviewState {
        let f = facts
        let input = Facts.overviewInput(year: displayedYear, window: 12, facts: f, calendar: calendar)
        return OverviewStore.state(vault: vault, year: displayedYear,
                                   digest: Facts.digest(input), hasMaterial: !f.isEmpty)
    }

    /// 関連の四種。何も選んでいないときは空。
    public var relations: [RelationGroup] {
        selected.map { Relations.of(snapshot, path: $0, year: displayedYear) } ?? []
    }

    // MARK: 編集（設計書 8.3）

    /// ⌘N の入力欄を出しているか。
    public var creating = false
    /// 作れなかった理由。入力欄の中と、シートを閉じた後は木の右側の帯にも出す
    /// （索引が失敗する経路はシートが閉じた後に理由が付くため）。
    public private(set) var creationError: String?
    /// 作った節点の path。索引へ載って選べるようになったら原文表示にする——
    /// 関門の前で `showsRaw` へ直接立てると、移動を取り消したときに元の節点の
    /// 表示モードまで変わってしまう(select(_:) は関門を通った後にしか動かない)。
    private var showsRawOnArrival: String?

    /// ⌘N の入力欄を開く。**前回の理由を持ち越さない。**消さずに開くと、次に
    /// 作ろうとしている節点とは無関係な、前回の失敗が新しいシートに残ってしまう。
    public func beginCreating() {
        creationError = nil
        creating = true
    }

    /// 「やめる」。**名前の検証の理由もここで消す。**索引に載らなかった理由
    /// （「作りましたが、開けませんでした」）はシートより長生きさせたいが、
    /// 入力欄の中で完結する検証の理由は、シートと寿命を共にすべきである——
    /// 二つを同じ欄に出す以上、取り消したのに前の入力の文句が原稿の上に
    /// 残るのは筋が通らない。
    public func cancelCreating() {
        creating = false
        creationError = nil
    }

    /// 節点を作って原文で開く(設計書 8.3)。**未保存の編集があるときは関門を通す。**
    @discardableResult
    public func createNode(named name: String) -> Bool {
        creationError = nil
        do {
            let path = try NodeCreator.create(in: vault, kind: kind, name: name, year: year)
            creating = false
            // 索引へ載せてから開く。載る前に選ぶと「消えた節点」として弾かれる。
            let url = vault.appendingPathComponent(path)
            showsRawOnArrival = path
            Task { [weak self] in
                guard let self else { return }
                guard let ix = self.indexer else { return }
                do {
                    let s = try await ix.reindex([url])
                    self.apply(s)
                    self.requestSelect(path)
                } catch {
                    // ファイルはもうできている。「作れなかった」と言うと、同じ名前で
                    // もう一度作ろうとして「既にあります」に当たる。
                    self.showsRawOnArrival = nil
                    self.creationError = "作りましたが、開けませんでした。木から選び直してください。"
                }
            }
            return true
        } catch let e as NodeCreator.Failure {
            creationError = e.message
            return false
        } catch {
            creationError = "作れませんでした。ディレクトリの権限を確かめてください。"
            return false
        }
    }

    /// 未保存の編集。原文の欄が触っているあいだだけ在る。
    public private(set) var draft: Draft?
    /// `raw` を書いたときの token。`textToken` と一致していれば、読み込みが済んでいる。
    /// **-1 で始める。**0 で始めると、`load()` が索引を作っている最中——`raw` がまだ空の
    /// うち——に `isTextLoaded` が真になり、空から下書きを作れてしまう。そのまま保存すると
    /// **既に書いてある 世界.md を、打った分だけで置き換える。**
    private var loadedTextToken = -1
    /// 保存できなかった理由。行番号つきで欄の上に出す。
    public private(set) var saveError: String?
    /// 編集中の節点のファイルが外で書き換わった印。
    public private(set) var changedOutside = false

    /// 未保存の変更があるか。移動の関門はこれを見る。
    public var isDirty: Bool { draft?.isDirty ?? false }

    /// 保存できる状態か。**`save()` が実際に書く条件と同じものを使う。**
    /// 外の変更を知らせているあいだは、文字列が基準と同じでも上書きさせる——
    /// 帯が「⌘S で上書きします」と言っているのに ⌘S が押せない、という食い違いを避ける。
    public var canSave: Bool { isDirty || changedOutside }

    /// `raw` が今の選択の原文になっているか。**読み込みは非同期なので、選び直した直後は偽になる。**
    public var isTextLoaded: Bool { loadedTextToken == textToken }

    /// 原文の欄を触れるか。**下書きが今の選択のもので、かつ意図して残したものなら触れる。**
    /// 外でファイルが消された後に、壊れた front matter を直して書き戻す経路がここを通る。
    /// 触れなくすると、⌘S は検証で落ち、直す手段も無くなって行き止まりになる。
    ///
    /// **`isDirty` だけでは足りない。**汚れは「今の文字列が基準と違うか」でしかなく、
    /// 打ち直して基準へ戻せば消える。復旧の途中で一瞬でも基準へ戻ると、そこで
    /// 触れなくなり、次の一打も setter に拒まれて行き止まりになる。
    /// `changedOutside` は `apply(_:)` が「意図して下書きを残した」ときに立てる印で、
    /// `save()` が書き終えるまで下りない——**汚れの増減とは無関係に、この下書きを
    /// 残した理由そのものを覚えている。**これを併せて見ることで、復旧の途中で
    /// 文字列が一時的に基準へ戻っても欄は閉じない。
    ///
    /// **`draft != nil` だけでは緩すぎる。**保存直後の綺麗な下書きが残ったまま、外で
    /// 読み込みに失敗すると（例: 世界.md が非UTF-8へ書き換わる）、`changedOutside` は
    /// 立たない（`reloadText` は読み込みが失敗したとき比べない）ので、その下書きだけで
    /// 空欄が編集可能になることはない。
    public var canEdit: Bool { isTextLoaded || isDirty || changedOutside }

    /// 原文の欄が読み書きする口。下書きがまだ無ければ、その場で始める。
    public var editedText: String {
        get { draft?.text ?? raw }
        set {
            // **判断は store に置く。**欄を `disabled` にするのは見た目の話で、
            // 綺麗な下書きが残ったまま読み込みに失敗した状態では、ここへ書けること
            // 自体が穴である——書けば下書きが汚れ、`canSave` が真になり、⌘S が
            // 読めなかったファイルを打ち込んだ分だけで潰す。
            guard canEdit else { return }
            beginDraftIfNeeded()
            draft?.text = newValue
        }
    }

    /// 下書きを今の原文から始める。既に在れば何もしない。
    ///
    /// **読み込みが済むまで始めない。**`select(_:)` は `selected` を同期で変えるが、`raw` の
    /// 更新は `Task` の中である。その隙に打つと `Draft(path: 移動先, base: 移動元の原文)` が
    /// できあがり、**同じ型なら検証も通って、移動先の原稿を移動元の内容で上書きする。**
    public func beginDraftIfNeeded() {
        guard draft == nil, isTextLoaded else { return }
        draft = Draft(path: selected, base: raw)
    }

    /// 開いている節点が壊れているか。
    public var isBroken: Bool {
        selected.flatMap { snapshot.nodes[$0]?.flags.contains(.broken) } ?? false
    }

    /// 実際に原文を出すか。壊れた節点は原文だけが使えるので、選んだ区分けに関わらず原文である
    /// （設計書 4.4）。front matter が YAML として読めない以上、表示に出せる本文が無い。
    public var showsRawEffectively: Bool { isBroken || showsRaw }

    /// 保存する（設計書 8.3）。front matter を検証し、通ればファイルへ書く。
    /// 通らなければ**書かず**、行番号つきの理由を欄の上に出す。
    /// 戻り値は書けたかどうかで、移動の関門（課題 5）がこれを見る。
    @discardableResult
    public func save() -> Bool {
        guard let d = draft, canSave else {
            saveError = nil
            return true          // 書くものが無い。移ってよい
        }
        // 型は**パスの先頭**から引く。索引から引くと、外でファイルが消えたときに型が
        // nil になり、`validate(kind: nil)` が 世界.md 扱いで検証を素通しする——
        // 壊れた front matter のまま元のパスへ書き戻せてしまう。
        // 世界.md（path が nil）だけが front matter を持たない。
        let kind = d.path.flatMap { Kind(rawValue: String($0.prefix(while: { $0 != "/" }))) }
        if let e = d.validate(kind: kind) {
            saveError = e.line.map { "\($0) 行目: \(e.message)" } ?? e.message
            return false
        }
        // path は vault からの相対。Indexer.fileURL(of:) と同じ組み立てで、actor を待たない。
        let url = d.path.map { vault.appendingPathComponent($0) }
            ?? vault.appendingPathComponent("世界.md")
        do {
            try d.text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            // 書けない理由は system の言葉で来る。日本語だけの規則を守るため、こちらで言う。
            saveError = "書き込めません。ファイルの権限と空き容量を確かめてください。"
            return false
        }
        saveError = nil
        changedOutside = false
        draft = d.saved()
        raw = d.text
        // 監視が拾うのを待たず、その場で索引し直す。木と年表がすぐ追いつく。
        if d.path != nil {
            Task { [weak self] in
                guard let ix = self?.indexer else { return }
                guard let s = try? await ix.reindex([url]) else { return }
                self?.apply(s)
            }
        }
        return true
    }

    /// 未保存のまま移ろうとしたときの行き先（設計書 8.3、2026-09-06 の利用者の判断）。
    /// 答えを受け取ってから実行するので、行き先を覚えておく。
    public enum Passage: Equatable, Sendable {
        case node(String?)
        case closeWindow
    }
    /// 問いかけ中の行き先。nil ならダイアログは出ていない。
    public private(set) var pendingPassage: Passage?

    /// 節点を選ぶ。**移動の経路はすべてここを通す。**未保存なら尋ねる。
    /// `arrivedAs` は利用者が辿り着いた名前（検索の行、押したリンク）。
    public func requestSelect(_ path: String?, arrivedAs name: String? = nil) {
        guard path != selected else { return }
        // **`canSave` を見る。**`isDirty` だけだと、外で消された節点を抱えたまま
        // 文字列を基準へ戻した状態（汚れていないが `changedOutside`）で、唯一の写しを
        // 黙って捨てて移ってしまう。⌘S が書くものを持っているなら、必ず尋ねる。
        guard canSave else { return select(path, arrivedAs: name) }
        // **`pendingArrivedAs` は関門を通す要求だけに立てる。**先に立てて後から
        // `canSave` を見ると、拒否された要求の名前が残ったまま次の要求の行き先へ
        // 紛れ込む（保留中に別の要求が来て、間に合わなかった要求の名前だけ生き残る）。
        pendingPassage = .node(path)
        pendingArrivedAs = name
    }

    /// 「保存して移る」。**通らなければ移らず、問いを残す。**
    public func passageSaveAndGo() {
        guard save() else { return }
        commitPassage()
    }

    /// 「保存せず移る」。**編集を捨てる。取り消せない。**
    public func passageDiscardAndGo() {
        draft = nil
        saveError = nil
        changedOutside = false
        commitPassage()
    }

    /// 「やめる」。編集も選択もそのまま。
    public func passageCancel() { pendingPassage = nil }

    private func commitPassage() {
        guard let p = pendingPassage else { return }
        pendingPassage = nil
        let name = pendingArrivedAs
        pendingArrivedAs = nil
        switch p {
        case let .node(path): select(path, arrivedAs: name)
        case .closeWindow: closeAfterPassage()      // 課題 6
        }
    }

    /// 関門を抜けたので閉じてよい、という印。AppKit の橋がこれを見る。
    public private(set) var wantsClose = false

    /// 窓を閉じてよいか。**未保存なら閉じさせず、問いを出す。**
    /// AppKit の `windowShouldClose(_:)` がこれを呼ぶ。
    public func requestClose() -> Bool {
        guard canSave else { return true }   // 移動の関門と同じ述語を使う
        pendingPassage = .closeWindow
        return false
    }

    /// 三択のどれかを通って、閉じてよくなった。
    func closeAfterPassage() { wantsClose = true }

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

    /// 関門を抜けた後にだけ呼ぶ。**外からは `requestSelect(_:)` を使う。**
    func select(_ path: String?, arrivedAs name: String? = nil) {
        guard path != selected else { return }
        if let path {
            guard let n = snapshot.nodes[path] else { return }
            kind = n.kind
            reveal(path)
            // 作った節点に実際に着いたときだけ原文表示にする(設計書 8.3)。関門の前で
            // 立てると、移動を取り消しても元の節点の表示モードが変わってしまう。
            if path == showsRawOnArrival {
                showsRaw = true
                showsRawOnArrival = nil
            }
        }
        // 移った先の原文で始め直す。未保存のまま移る経路は課題 5 で塞ぐ。
        draft = nil
        saveError = nil
        changedOutside = false
        // 辿り着いた名前は選択と寿命を共にする。戻る一手も同じ（設計書 7 節）。
        arrivedAs = name
        returnYear = nil
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
        requestSelect(pp)
    }

    public func stop() async {
        // 予約を取り消して、その場で書き切る。**窓が閉じると Task は空振りする**ので、
        // 動かして 1 秒以内に閉じた年と尺がここを通らないと消える（設計書 4.2）。
        yearWriteTask?.cancel()
        scaleWriteTask?.cancel()
        persistYear()
        persistScale()
        await indexer?.stopWatching()
    }

    // MARK: 年表（設計書 8.5、8.6、11 節）

    /// 年を動かしてからファイルへ書き戻すまでの間（設計書 4.2）。試験のためだけに縮める。
    /// 窓ごとの値である。プロセス全体で共有すると、並行に走る試験どうしが互いの値を
    /// 書き換え合う（Swift Testing は既定でテストを並行に走らせる）。
    public var writeDelay: Duration = .seconds(1)

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
        Timeline.rows(snapshot, selected: selected, kind: kind, year: displayedYear)
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
        let root = selected.flatMap { snapshot.nodes[$0]?.displayName(at: displayedYear) } ?? kind.rawValue
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
        let delay = writeDelay
        yearWriteTask?.cancel()
        yearWriteTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.persistYear()
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
        let delay = writeDelay
        scaleWriteTask?.cancel()
        scaleWriteTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.persistScale()
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

    /// 試験のための入口。監視は FSEvents で待ち時間が読めないので、その場で索引し直す。
    /// **製品の経路では使わない。**監視と `save()` が同じ `apply(_:)` を通る。
    ///
    /// **本文の読み直しまで待ってから戻る。**`apply(_:)` は読み直しを別の `Task` に
    /// 予約するので、そのまま戻ると試験は `raw` や `changedOutside` を古いまま検べる。
    /// 正しい実装でも落ちる試験になり、監視が先回りしたときだけ通るような結果にもなる。
    /// 監視を止める。**索引し直しを試験が自分で起こす場合に要る。**本物の監視が横から
    /// 索引し直すと `textToken` が進み、こちらが待っている再読み込みが
    /// `guard token == textToken` で黙って戻る——並行して走る試験の負荷が高いときだけ
    /// 起きるので、単独で流すと再現しない。
    func stopWatchingForTest() async { await indexer?.stopWatching() }

    func reindexForTest(_ files: [URL]) async {
        guard let ix = indexer, let s = try? await ix.reindex(files) else { return }
        apply(s)
        await reloadText(token: textToken, target: selected)
    }

    /// 同じく試験のための入口。全体を索引し直す。
    func rebuildForTest() async {
        guard let ix = indexer, let s = try? await ix.rebuild() else { return }
        apply(s)
        await reloadText(token: textToken, target: selected)
    }

    private func apply(_ s: Snapshot) {
        snapshot = s
        // 開いていた節点が消えたら、概要へ戻す。
        // **ただし未保存の編集を抱えているときは選択を保つ。**選択だけ外すと、下書きは
        // 消えた節点のものなのに画面は概要になり、⌘S が画面に見えない場所へ書く。
        // 抱えたままなら、⌘S でその場所へ書き戻せる——それが利用者の望む復旧である。
        //
        // **下書きは常に今の選択のものである。**この不変条件を破ると、編集文字列と
        // 保存先が食い違う。選択を外すときは、汚れていない下書きも一緒に捨てる——
        // `save()` は綺麗な下書きを残すので、保存した直後に外で消されるとここへ来る。
        if let p = selected, s.nodes[p] == nil {
            // **`isDirty` だけを見ない。**「わざと抱えている」ことと「いま汚れている」ことは
            // 別である——利用者が文字列を基準へ戻すと汚れは消えるが、抱えている理由は
            // 変わらない。`changedOutside` がその印で、`save()` が書き終えるまで下りない。
            // ここを `isDirty` だけにすると、基準へ戻したあとに別のファイルの変更で
            // 索引が走っただけで、復旧用の下書きと保存先が消える。
            if draft?.path == p, isDirty || changedOutside {
                changedOutside = true
            } else {
                selected = nil
                draft = nil
                saveError = nil
                changedOutside = false
                arrivedAs = nil
                returnYear = nil
            }
        }
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
            let url = vault.appendingPathComponent("世界.md")
            // 無ければ空でよい。まだ書いていないだけである（設計書 4.1）。
            // **読めないのは別である。**空と扱うと、打って保存した時点で元の中身が消える。
            if FileManager.default.fileExists(atPath: url.path) {
                do { loaded = try String(contentsOf: url, encoding: .utf8) }
                catch { failure = "世界.md が UTF-8 として読めません。" }
            }
            whole = loaded
        }
        guard token == textToken else { return }
        text = loaded
        raw = whole
        textError = failure
        // **読めなかったときは「読み込み済み」にしない。**読めない原稿を空欄と勘違いして
        // 打ち直し、保存で元のファイルを潰す——という経路をここで塞ぐ。
        if failure == nil { loadedTextToken = token }
        // 編集中なら、その節点のファイルの中身そのものと基準を比べる（設計書 8.3）。
        // **索引が走ったこと自体を「外で変わった」と読まない。**年を動かすと 世界.yaml が
        // 書かれて全体の索引が走るので、それを外の変更と数えると警告が出続ける。
        // **読み込みが失敗したときは比べない。**failure 時の whole は空文字であり、
        // 「外がこう変わった」という中身ではない。ここを素通しすると、非UTF-8へ
        // 書き換えられた原稿が空の基準へ丸められ、下書きが汚れていなければ静かに
        // 空欄へ差し替わってしまう。
        // **既に抱えているなら、比べ直さない。**`Draft.merging` は汚れていなければ
        // 外の内容を採るが、それは「まだ抱えていない」ときの正しさである。抱えている
        // 最中に利用者が文字列を基準へ戻すと汚れが消えるので、無関係な索引が走った
        // だけで、書き戻すための旧本文が外の内容へ差し替わってしまう。
        // 一度抱えたら、保存するか捨てるかを利用者が選ぶまで抱えたままにする。
        if failure == nil, !changedOutside, let d = draft, d.path == target {
            let (next, outside) = d.merging(external: whole)
            draft = next
            if outside { changedOutside = true }
        }
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
