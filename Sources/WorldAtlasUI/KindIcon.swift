import SwiftUI
import WorldAtlasCore

/// 年表の出来事の記号と同じ菱形。Stage 3 の年表もこれを使う。
public struct DiamondShape: Shape {
    public init() {}
    public func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.midY))
        p.closeSubpath()
        return p
    }
}

/// 左のレールに並ぶ七つの型のアイコン。線で描く前提で、塗りは持たない。
/// 等高線が場所、旗が勢力、人が人物、櫃がアイテム、冊子が書籍、石碑が法律、菱形が出来事。
public struct KindIcon: Shape {
    public var kind: Kind
    public init(kind: Kind) { self.kind = kind }

    public func path(in r: CGRect) -> Path {
        // 0…1 の座標で描き、最後に枠へ写す。枠は正方形でなくてもよい。
        let s = min(r.width, r.height)
        let o = CGPoint(x: r.midX - s / 2, y: r.midY - s / 2)
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x * s, y: o.y + y * s) }
        var p = Path()
        switch kind {
        case .place:
            // 等高線。三重の楕円。
            for i in 0..<3 {
                let d = CGFloat(i) * 0.13
                p.addEllipse(in: CGRect(x: o.x + s * (0.10 + d), y: o.y + s * (0.22 + d * 0.8),
                                        width: s * (0.80 - d * 2), height: s * (0.56 - d * 1.6)))
            }
        case .polity:
            // 旗。竿と三角の吹き流し。
            p.move(to: pt(0.26, 0.08)); p.addLine(to: pt(0.26, 0.92))
            p.move(to: pt(0.26, 0.14)); p.addLine(to: pt(0.82, 0.30))
            p.addLine(to: pt(0.26, 0.46)); p.closeSubpath()
        case .person:
            // 人。頭と肩。
            p.addEllipse(in: CGRect(x: o.x + s * 0.34, y: o.y + s * 0.14, width: s * 0.32, height: s * 0.32))
            p.move(to: pt(0.16, 0.88))
            p.addQuadCurve(to: pt(0.84, 0.88), control: pt(0.50, 0.42))
        case .item:
            // 櫃。箱と蓋の線と留め金。
            p.addRoundedRect(in: CGRect(x: o.x + s * 0.14, y: o.y + s * 0.26, width: s * 0.72, height: s * 0.50),
                             cornerSize: CGSize(width: s * 0.06, height: s * 0.06))
            p.move(to: pt(0.14, 0.44)); p.addLine(to: pt(0.86, 0.44))
            p.move(to: pt(0.44, 0.44)); p.addLine(to: pt(0.44, 0.58))
            p.addLine(to: pt(0.56, 0.58)); p.addLine(to: pt(0.56, 0.44))
        case .book:
            // 冊子。表紙と背と頁。
            p.addRect(CGRect(x: o.x + s * 0.20, y: o.y + s * 0.16, width: s * 0.60, height: s * 0.68))
            p.move(to: pt(0.34, 0.16)); p.addLine(to: pt(0.34, 0.84))
            p.move(to: pt(0.44, 0.36)); p.addLine(to: pt(0.70, 0.36))
            p.move(to: pt(0.44, 0.50)); p.addLine(to: pt(0.70, 0.50))
        case .law:
            // 石碑。上が丸い板と刻んだ二本の線。
            p.move(to: pt(0.24, 0.88)); p.addLine(to: pt(0.24, 0.36))
            p.addQuadCurve(to: pt(0.76, 0.36), control: pt(0.50, 0.06))
            p.addLine(to: pt(0.76, 0.88)); p.closeSubpath()
            p.move(to: pt(0.36, 0.50)); p.addLine(to: pt(0.64, 0.50))
            p.move(to: pt(0.36, 0.64)); p.addLine(to: pt(0.64, 0.64))
        case .event:
            p = DiamondShape().path(in: r)
        }
        return p
    }
}
