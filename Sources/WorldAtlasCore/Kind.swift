/// 節点の型。rawValue が vault の中のディレクトリ名である。
public enum Kind: String, CaseIterable, Sendable, Codable {
    case place = "場所"
    case polity = "勢力"
    case person = "人物"
    case item = "アイテム"
    case book = "書籍"
    case law = "法律"
    case event = "出来事"

    /// 型の並び順。左のレールとこの順で並ぶ。
    public var order: Int { Kind.allCases.firstIndex(of: self)! }
}

/// 索引が節点に付ける印。複数が同時に付くので集合で持ち、空なら正常である。
/// 壊れている と 名前の不一致 はファイル単位で決まり索引に持つ。重複 は保存名の一覧から
/// snapshot を作るときに計算し、索引には持たない。
public enum Flag: String, Sendable, Codable, Hashable {
    case broken = "壊れている"
    case nameMismatch = "名前の不一致"
    case duplicate = "重複"
}
