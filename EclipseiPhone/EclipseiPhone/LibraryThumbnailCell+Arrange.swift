//
//  LibraryThumbnailCell+Arrange.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Arrange Mode (draggable wiggle)

extension LibraryThumbnailCell {

    private static let wiggleKey = "eclipse.arrange.wiggle"
    private static let wiggleDuration: CFTimeInterval = 0.28
    /// Home-Screen-style tilt: readable as "grab me" without looking broken.
    private static let wiggleAngle: CGFloat = 1.1 * .pi / 180

    /// Marks the tile as draggable while the grid is in arrange mode.
    func setArranging(_ arranging: Bool) {
        if arranging {
            startArrangeWiggle()
        } else {
            stopArrangeWiggle()
        }
    }

    /// Clears the wiggle. Called on every reconfigure so recycled cells stay still.
    func stopArrangeWiggle() {
        contentView.layer.removeAnimation(forKey: Self.wiggleKey)
    }

    private func startArrangeWiggle() {
        guard contentView.layer.animation(forKey: Self.wiggleKey) == nil else { return }
        let wiggle = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        wiggle.values = [-Self.wiggleAngle, Self.wiggleAngle, -Self.wiggleAngle]
        wiggle.duration = Self.wiggleDuration
        wiggle.repeatCount = .infinity
        wiggle.isRemovedOnCompletion = false
        // Stagger the phase so the grid shimmers instead of pulsing in lockstep.
        wiggle.timeOffset = .random(in: 0...Self.wiggleDuration)
        contentView.layer.add(wiggle, forKey: Self.wiggleKey)
    }
}
