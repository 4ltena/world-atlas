import Foundation
import WorldAtlasCore

/// 未保存の編集（設計書 8.3）。原文の欄が持つ唯一の状態で、判断はここに集める。
/// **`VaultStore` にも View にも同じ判断を置かない。**
public struct Draft: Equatable, Sendable {
    /// 編集している節点の vault からの相対パス。`世界.md` を編集しているときは nil。
    public var path: String?
    /// 読み込んだときの原文。汚れの基準であり、外の変更を見分ける基準でもある。
    public private(set) var base: String
    /// 編集中の文字列。
    public var text: String

    public init(path: String?, base: String) {
        self.path = path
        self.base = base
        self.text = base
    }

    /// 保存していない変更があるか。**差分ではなく値で見る**ので、打って戻せば汚れも落ちる。
    public var isDirty: Bool { text != base }

    /// 保存できる形か。通らなければその誤りを返す。
    /// `世界.md`（`kind` が nil）は front matter を持たないので素通しする。
    public func validate(kind: Kind?) -> FrontMatterError? {
        guard let kind else { return nil }
        do {
            _ = try FrontMatter.parse(text, kind: kind)
            return nil
        } catch {
            return error
        }
    }

    /// 書いた後の姿。基準を今の文字列へ動かす。
    public func saved() -> Draft {
        var d = self
        d.base = d.text
        return d
    }

    /// 外でファイルが書き換わったときの扱い(設計書 8.3)。
    ///
    /// - 中身が基準と同じなら何も起きていない。**自分が書いたものを読み直した場合もここに入る。**
    /// - 編集していなければ外の内容をそのまま取る。
    /// - 編集していれば**編集中の文字列を守り**、知らせる印だけを返す。
    public func merging(external: String) -> (draft: Draft, changedOutside: Bool) {
        guard external != base else { return (self, false) }
        // **これは「まだ抱えていない」ときの正しさである。**呼ぶ側が既に外の変更を
        // 抱えているなら、ここへ来てはいけない——利用者が文字列を基準へ戻しただけで
        // 汚れが消え、書き戻すための旧本文を手放してしまう。`VaultStore.reloadText` が
        // `changedOutside` を見て入口で止めている。
        guard isDirty else { return (Draft(path: path, base: external), false) }
        return (self, true)
    }
}
