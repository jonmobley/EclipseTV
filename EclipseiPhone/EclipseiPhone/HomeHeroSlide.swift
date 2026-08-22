//
//  HomeHeroSlide.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// One page in the Home marketing carousel.
struct HomeHeroSlide: Equatable, Hashable {
    let title: String
    let subtitle: String
    /// Asset catalog name, or `nil` for a gradient + symbol slide.
    let imageName: String?
    /// SF Symbol used when `imageName` is nil.
    let systemImage: String?
    /// Distinct muted fill so the card reads against the Home background.
    let palette: Palette

    /// Brand + feature pages shown on Home.
    static let all: [HomeHeroSlide] = [
        HomeHeroSlide(
            title: "Eclipse",
            subtitle: "Present media, web, and camera on any screen.",
            imageName: nil,
            systemImage: "tv.fill",
            palette: .indigo
        ),
        HomeHeroSlide(
            title: "Shows",
            subtitle: "Create a show and connect with HDMI or AirPlay.",
            imageName: nil,
            systemImage: "rectangle.stack.fill",
            palette: .teal
        ),
        HomeHeroSlide(
            title: "Music",
            subtitle: "Keep ambient Background Music ready while you present.",
            imageName: nil,
            systemImage: "music.note",
            palette: .plum
        )
    ]
}

extension HomeHeroSlide {
    /// Per-slide muted tints — lighter and more chromatic than the Home black.
    enum Palette: Equatable, Hashable {
        /// Brand / TV — steel indigo.
        case indigo
        /// Shows / connect — slate teal.
        case teal
        /// Ambient music — dusk plum.
        case plum

        /// Top-to-bottom gradient stops.
        var gradientColors: [UIColor] {
            switch self {
            case .indigo: Self.indigoFill
            case .teal: Self.tealFill
            case .plum: Self.plumFill
            }
        }

        /// Solid fallback shown before the gradient layer composites.
        var fallbackColor: UIColor {
            gradientColors.last ?? UIColor(white: 0.22, alpha: 1)
        }

        private static let indigoFill = [
            UIColor(red: 0.22, green: 0.32, blue: 0.58, alpha: 1),
            UIColor(red: 0.12, green: 0.20, blue: 0.40, alpha: 1)
        ]
        private static let tealFill = [
            UIColor(red: 0.14, green: 0.46, blue: 0.42, alpha: 1),
            UIColor(red: 0.08, green: 0.28, blue: 0.28, alpha: 1)
        ]
        private static let plumFill = [
            UIColor(red: 0.44, green: 0.24, blue: 0.48, alpha: 1),
            UIColor(red: 0.28, green: 0.14, blue: 0.34, alpha: 1)
        ]
    }
}
