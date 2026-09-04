public struct Alias: Equatable, Sendable, Codable {
    public var from: Int
    public var name: String
    public init(from: Int, name: String) { self.from = from; self.name = name }
}

public struct Mark: Equatable, Sendable, Codable {
    public var year: Int
    public var label: String
    public init(year: Int, label: String) { self.year = year; self.label = label }
}

/// 支配。to が nil なら現在まで。
public struct Rule: Equatable, Sendable, Codable {
    public var from: Int
    public var to: Int?
    public var polity: String
    public init(from: Int, to: Int?, polity: String) { self.from = from; self.to = to; self.polity = polity }
}

/// 由来。origin から year に kind（分離・統合・継承・再建など）でこの節点へ。
public struct Lineage: Equatable, Sendable, Codable {
    public var year: Int
    public var kind: String
    public var origin: String
    public init(year: Int, kind: String, origin: String) { self.year = year; self.kind = kind; self.origin = origin }
}

/// 一つの Markdown ファイルから読めた節点。
public struct Node: Equatable, Sendable, Codable {
    /// 保存名。ファイル名と一致するべきもの。
    public var name: String
    public var kind: Kind
    /// 種別。都市、宿、法、巻など自由な語。
    public var category: String
    public var from: Int
    /// nil は「現在」。点の出来事は from と同じ値。
    public var to: Int?
    /// `年:` で書かれた、期間を持たない節点。
    public var isPoint: Bool
    public var aliases: [Alias]
    public var parent: String?
    public var rules: [Rule]
    public var lineages: [Lineage]
    public var marks: [Mark]
    public var body: String

    public init(name: String, kind: Kind, category: String, from: Int, to: Int?, isPoint: Bool = false,
                aliases: [Alias] = [], parent: String? = nil, rules: [Rule] = [], lineages: [Lineage] = [],
                marks: [Mark] = [], body: String = "") {
        self.name = name; self.kind = kind; self.category = category; self.from = from; self.to = to
        self.isPoint = isPoint; self.aliases = aliases; self.parent = parent; self.rules = rules
        self.lineages = lineages; self.marks = marks; self.body = body
    }

    /// year にこの節点が存在するか。点なら同じ年だけ。
    public func exists(at year: Int) -> Bool {
        if isPoint { return year == from }
        if let to { return from <= year && year <= to }
        return from <= year
    }
}

public struct FrontMatterError: Error, Equatable, Sendable {
    /// ファイル内の行番号（1 始まり）。分からなければ nil。
    public var line: Int?
    public var message: String
    public init(line: Int? = nil, message: String) { self.line = line; self.message = message }
}
