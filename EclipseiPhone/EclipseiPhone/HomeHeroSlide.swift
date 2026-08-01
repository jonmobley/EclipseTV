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

    /// Brand + feature pages shown on Home.
    static let all: [HomeHeroSlide] = [
        HomeHeroSlide(
            title: "Eclipse",
            subtitle: "Present media, web, and camera on any screen.",
            imageName: nil,
            systemImage: "tv.fill"
        ),
        HomeHeroSlide(
            title: "Shows",
            subtitle: "Create a show and connect with HDMI or AirPlay.",
            imageName: nil,
            systemImage: "rectangle.stack.fill"
        ),
        HomeHeroSlide(
            title: "Music",
            subtitle: "Keep ambient Background Music ready while you present.",
            imageName: nil,
            systemImage: "music.note"
        )
    ]
}
