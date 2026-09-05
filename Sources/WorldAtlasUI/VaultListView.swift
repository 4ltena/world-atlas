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

    public init() {}

    private var recents: [RecentVault] { RecentVaults.decode(stored) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if recents.isEmpty {
                ContentUnavailableView("まだ vault がありません", systemImage: "square.stack.3d.up",
                                       description: Text("既に Markdown を書いたディレクトリを開くか、新しく作ります"))
            } else {
                List {
                    ForEach(recents) { v in
                        Button { open(v.url) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(v.world).font(.headline)
                                Text(v.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            // 一覧から外すだけで、ディレクトリは消さない（設計書 4.1）。
                            Button("一覧から外す") { stored = RecentVaults.encode(RecentVaults.remove(recents, path: v.path)) }
                        }
                    }
                }
            }
            Divider()
            HStack {
                Button("開く…") { pickingForNew = false; picking = true }
                Button("新規作成…") { newWorldName = ""; newCalendarName = ""; creating = true }
                Spacer()
            }
            .padding(12)
        }
        .frame(minWidth: 420, minHeight: 320)
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

    /// 先に世界の名前と基準暦の名前を尋ね、そのあとで置き場を選ぶ（設計書 4.1）。
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
        do {
            let text = try String(contentsOf: url.appendingPathComponent("世界.yaml"), encoding: .utf8)
            let world = try WorldFile.parse(text)
            remember(url, world: world.name)
            openWindow(value: url)
        } catch {
            failure = "\(url.lastPathComponent) を vault として開けません（世界.yaml を読めませんでした）。"
                + "世界.yaml のあるディレクトリを選び直すか、「新規作成…」でこのディレクトリを vault にしてください。"
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
