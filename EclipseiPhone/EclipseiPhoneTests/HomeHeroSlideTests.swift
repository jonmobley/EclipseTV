//
//  HomeHeroSlideTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

struct HomeHeroSlideTests {

    @Test func eachSlideUsesADistinctPalette() {
        let palettes = HomeHeroSlide.all.map(\.palette)
        #expect(Set(palettes).count == palettes.count)
        #expect(palettes == [.indigo, .teal, .plum])
    }

    @Test func palettesStayApartFromNearBlackAndEachOther() {
        let fills = HomeHeroSlide.all.map(\.palette.gradientColors)
        for colors in fills {
            #expect(colors.count == 2)
            for color in colors {
                #expect(luminance(of: color) > 0.12)
            }
        }
        let tops = fills.compactMap(\.first)
        #expect(tops.count == 3)
        #expect(distance(tops[0], tops[1]) > 0.15)
        #expect(distance(tops[0], tops[2]) > 0.15)
        #expect(distance(tops[1], tops[2]) > 0.15)
    }

    private func luminance(of color: UIColor) -> CGFloat {
        let rgb = components(of: color)
        return 0.2126 * rgb.r + 0.7152 * rgb.g + 0.0722 * rgb.b
    }

    private func distance(_ a: UIColor, _ b: UIColor) -> CGFloat {
        let lhs = components(of: a)
        let rhs = components(of: b)
        let dr = lhs.r - rhs.r
        let dg = lhs.g - rhs.g
        let db = lhs.b - rhs.b
        return sqrt(dr * dr + dg * dg + db * db)
    }

    private func components(of color: UIColor) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        #expect(color.getRed(&r, green: &g, blue: &b, alpha: &a))
        return (r, g, b)
    }
}
