import SwiftUI
import Testing
import WorldAtlasCore
@testable import WorldAtlasUI

@Suite @MainActor struct KindIconTests {
    let box = CGRect(x: 0, y: 0, width: 100, height: 100)

    @Test func everyKindDrawsSomething() {
        for k in Kind.allCases {
            let p = KindIcon(kind: k).path(in: box)
            #expect(!p.isEmpty, "\(k.rawValue) の図形が空である")
        }
    }

    @Test func everyKindStaysInsideItsBox() {
        for k in Kind.allCases {
            let b = KindIcon(kind: k).path(in: box).boundingRect
            #expect(box.insetBy(dx: -0.5, dy: -0.5).contains(b), "\(k.rawValue) が枠をはみ出す: \(b)")
        }
    }

    @Test func kindsDrawDifferentShapes() {
        let rects = Kind.allCases.map { KindIcon(kind: $0).path(in: box).description }
        #expect(Set(rects).count == Kind.allCases.count, "同じ図形を使い回している型がある")
    }

    @Test func eventUsesTheSharedDiamond() {
        #expect(KindIcon(kind: .event).path(in: box).description == DiamondShape().path(in: box).description)
    }
}
