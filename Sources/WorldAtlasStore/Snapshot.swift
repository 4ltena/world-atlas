import WorldAtlasCore

/// 索引から読めた一つの節点。本文は持たない。識別子は path。
public struct IndexedNode: Equatable, Sendable {
    /// vault からの相対パス。識別子。
    public var path: String
    /// 保存名。ファイル名と一致するべきもの。
    public var name: String
    public var kind: Kind
    public var category: String
    public var from: Int
    public var to: Int?
    public var isPoint: Bool
    /// front matter に書かれた親の保存名。
    public var parent: String?
    /// 解決した親の path。親が無い、見つからない、曖昧、型が違うときは nil。
    public var parentPath: String?
    public var aliases: [Alias]
    public var rules: [Rule]
    public var lineages: [Lineage]
    public var marks: [Mark]
    /// 空なら正常。
    public var flags: Set<Flag>

    public func displayName(at year: Int) -> String { asNode.displayName(at: year) }
    public func exists(at year: Int) -> Bool { asNode.exists(at: year) }
    /// 判断層へ渡すための Node（本文は空）。
    public var asNode: Node {
        Node(name: name, kind: kind, category: category, from: from, to: to, isPoint: isPoint,
             aliases: aliases, parent: parent, rules: rules, lineages: lineages, marks: marks)
    }
}

/// 画面が読む不変の値。索引が更新されるたびに丸ごと作り直す。鍵はすべて path。
public struct Snapshot: Sendable {
    public var world: World
    public var nodes: [String: IndexedNode]
    /// 保存名または別名 → その名を持つ節点の path。本文のリンクの解決に使う。二つ以上なら曖昧。
    public var names: [String: [String]]
    /// 保存名だけ → その名を持つ節点の path。重複の印、親、支配の解決に使う。
    public var savedNames: [String: [String]]
    /// 親の path → 子の path。開始年、同年は名前の順。
    public var children: [String: [String]]
    /// 型 → 型の直下の path。
    public var roots: [Kind: [String]]
    /// 参照元 path → 参照先 path（本文の出現順）。
    public var refs: [String: [String]]
    /// 参照先 path → 参照元 path（名前順）。
    public var backrefs: [String: [String]]
    /// 参照元 path → 解決できなかったリンクの文字列（曖昧なものを含む）。
    public var unresolved: [String: [String]]
    public var extent: Extent
    public var ignoredDirectories: Int

    public static let empty = Snapshot(
        world: World(name: "", baseCalendar: "", calendars: [], current: 1),
        nodes: [:], names: [:], savedNames: [:], children: [:], roots: [:], refs: [:], backrefs: [:],
        unresolved: [:], extent: Extent(lo: 1, hi: 2), ignoredDirectories: 0
    )

    /// 本文のリンク用。保存名でも別名でも引ける。一意のときだけ path を返す。
    public func path(ofName name: String) -> String? {
        guard let ps = names[name], ps.count == 1 else { return nil }
        return ps[0]
    }

    /// 親と支配用。保存名だけで引く。一意のときだけ path を返す。
    public func path(ofSavedName name: String) -> String? {
        guard let ps = savedNames[name], ps.count == 1 else { return nil }
        return ps[0]
    }

    public func node(savedName name: String) -> IndexedNode? {
        path(ofSavedName: name).flatMap { nodes[$0] }
    }

    /// year に path を支配している勢力。本人に支配が書かれていなければ親を遡る。
    /// 区間は [開始, 終了) で、終了が nil なら開区間。
    public func rulers(of path: String, at year: Int) -> [IndexedNode] {
        var cur = nodes[path]
        while let n = cur {
            if !n.rules.isEmpty {
                return n.rules
                    .filter { $0.from <= year && ($0.to.map { year < $0 } ?? true) }
                    .compactMap { node(savedName: $0.polity) }
            }
            cur = n.parentPath.flatMap { nodes[$0] }
        }
        return []
    }
}
