import SwiftUI
import UniformTypeIdentifiers
import WorldAtlasCore
import WorldAtlasStore

/// 起動時に出る窓。最近使った vault を並べ、開く・新規作成・一覧から外すができる。
public struct VaultListView: View {
    @AppStorage("recentVaults") private var stored: String = "[]"
    @Environment(\.openWindow) private var openWindow

    @State private var picking = false
    // 選んだ先を新規作成として扱うか。fileImporter は一つの View に一つだけ置く。
    @State private var pickingForNew = false
    @State private var creating = false
    @State private var newWorldName = ""
    @State private var newCalendarName = ""
    @State private var failure: String?
    @State private var find = ""

    public init() {}

    private var recents: [RecentVault] { RecentVaults.decode(stored) }

    /// 世界名とパスの部分一致で絞る。一覧は上限 20 件なので、単純な走査でよい。
    private var shown: [RecentVault] {
        let q = find.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return recents }
        return recents.filter {
            $0.world.localizedCaseInsensitiveContains(q) || $0.path.localizedCaseInsensitiveContains(q)
        }
    }

    public var body: some View {
        HStack(spacing: 0) {
            side
            main
        }
        .frame(minWidth: 720, minHeight: 460)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            let forNew = pickingForNew
            pickingForNew = false
            if case let .success(url) = result {
                if forNew { create(at: url) } else { open(url) }
            }
        }
        .sheet(isPresented: $creating) { newVaultSheet }
        .alert("開けません", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("閉じる", role: .cancel) {}
        } message: {
            Text(failure ?? "")
        }
    }

    /// 左の欄。上にアプリの印と名前と版、その下に行き先(いまは「世界」の一つだけ)。
    /// 設定は Stage 6 なので、まだ無い行き先は置かない。
    private var side: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                KindIcon(kind: .place)
                    .stroke(style: StrokeStyle(lineWidth: 1.3, lineJoin: .round))
                    .frame(width: 34, height: 34)
                    .foregroundStyle(Palette.accent)
                VStack(alignment: .leading, spacing: 0) {
                    Text("world-atlas").font(.title3)
                    Text("0.2.0").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 26)

            Text("世界")
                .padding(.horizontal, 12).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 5))
                .foregroundStyle(Palette.accent)
            Spacer()
        }
        .padding(14)
        .frame(width: 232)
        .background(Palette.sidebar)
    }

    private var main: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("vault を探す", text: $find)
                        .textFieldStyle(.plain)
                }
                Spacer(minLength: 0)
                Button("開く…") { pickingForNew = false; picking = true }
                Button("新規作成…") { newWorldName = ""; newCalendarName = ""; creating = true }
            }
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 14)
            Rectangle().fill(Palette.rule).frame(height: 1).padding(.horizontal, 20)

            if shown.isEmpty {
                ContentUnavailableView(
                    recents.isEmpty ? "まだ vault がありません" : "見つかりません",
                    systemImage: "square.stack.3d.up",
                    description: Text(recents.isEmpty
                        ? "既に Markdown を書いたディレクトリを開くか、新しく作ります"
                        : "名前かパスの一部で探せます"))
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(shown) { row($0) }
                    }
                    .padding(12)
                }
            }
            Spacer(minLength: 0)
        }
        .background(Palette.ground)
    }

    /// 一覧の一行。左に色の四角、右に世界名・パス・件数と年の範囲を同じ左端で三段に積む
    /// (設計書 4.1)。三段目は一度開いた vault にだけ出る。
    private func row(_ v: RecentVault) -> some View {
        Button { open(v.url) } label: {
            HStack(alignment: .top, spacing: 13) {
                Text(String(v.world.prefix(1)))
                    .frame(width: 34, height: 34)
                    .background(Palette.polity(RecentVaults.colorIndex(of: v.path, count: Palette.polityCount)),
                                in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(.black)
                VStack(alignment: .leading, spacing: 1) {
                    Text(v.world)
                    Text(v.path).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.head)
                    if let n = v.nodes, let from = v.from, let to = v.to {
                        Text("\(n) 件　\(from)–\(to) 年")
                            .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            // 一覧から外すだけで、ディレクトリは消さない(設計書 4.1)。
            Button("一覧から外す") { stored = RecentVaults.encode(RecentVaults.remove(recents, path: v.path)) }
        }
    }

    /// 先に世界の名前と基準暦の名前を尋ね、そのあとで置き場を選ぶ(設計書 4.1)。
    private var newVaultSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("新しい世界").font(.headline)
            TextField("世界の名前", text: $newWorldName)
            TextField("基準暦の名前", text: $newCalendarName)
            Text("暦は一つで始めます。増やすときは 世界.yaml を直接書き換えます。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("やめる", role: .cancel) { creating = false }
                Button("置き場を選ぶ…") { creating = false; pickingForNew = true; picking = true }
                    .keyboardShortcut(.defaultAction)
                    .disabled(newWorldName.trimmingCharacters(in: .whitespaces).isEmpty
                              || newCalendarName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func open(_ url: URL) {
        let worldFile = url.appendingPathComponent("世界.yaml")
        do {
            let text = try String(contentsOf: worldFile, encoding: .utf8)
            let world = try WorldFile.parse(text)
            remember(url, world: world.name)
            openWindow(value: url)
        } catch {
            let fm = FileManager.default
            var isDirectory: ObjCBool = false
            // ディレクトリ自体が無いのか、世界.yaml が無いのか、あるが読めないのかで、
            // 次にできることが違う。最近使った一覧の行は、移した・捨てた vault を
            // 指していることがあり、それが実際には一番起こりやすい。
            if !fm.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                // 選び直しも新規作成もこの場所には効かない（フォルダ選択は既存フォルダしか
                // 選べず、同じ場所は作れない）ので勧めない。
                failure = "\(url.lastPathComponent) が見つかりません。"
                    + "移したのなら「開く…」で新しい場所を選び直し、要らないなら行を副ボタンで押して「一覧から外す」を選んでください。"
            } else if !isDirectory.boolValue {
                failure = "\(url.lastPathComponent) はディレクトリではありません。vault はディレクトリです。"
                    + "「開く…」で選び直すか、行を副ボタンで押して「一覧から外す」を選んでください。"
            } else if fm.fileExists(atPath: worldFile.path) {
                // 在るときは新規作成が断られる（VaultCreator は存在するだけで拒否する）ので勧めない。
                let detail = (error as? FrontMatterError).map { e in
                    e.line.map { "\($0) 行目: \(e.message)" } ?? e.message
                } ?? error.localizedDescription
                failure = "\(url.lastPathComponent) の 世界.yaml を読めませんでした。直してから開き直してください。\n\n理由: \(detail)"
            } else {
                failure = "\(url.lastPathComponent) を vault として開けません（世界.yaml がありません）。"
                    + "世界.yaml のあるディレクトリを選び直すか、「新規作成…」でこのディレクトリを vault にしてください。"
            }
        }
    }

    private func create(at url: URL) {
        do {
            try VaultCreator.create(at: url,
                                    worldName: newWorldName.trimmingCharacters(in: .whitespaces),
                                    calendarName: newCalendarName.trimmingCharacters(in: .whitespaces))
            open(url)
        } catch let e as VaultCreator.Failure {
            failure = e.message
        } catch {
            // 日本語で何が起きたかと次の一手を先に出し、OS の理由は手がかりとして添える。
            // `\(error)` は NSError の生の記述で、英語のまま出ることがある。
            failure = "この場所には vault を作れませんでした。書き込みできる別のディレクトリを選んでください。\n\n理由: \(error.localizedDescription)"
        }
    }

    private func remember(_ url: URL, world: String) {
        stored = RecentVaults.encode(RecentVaults.touch(recents, path: url.path, world: world, now: Date()))
    }
}
