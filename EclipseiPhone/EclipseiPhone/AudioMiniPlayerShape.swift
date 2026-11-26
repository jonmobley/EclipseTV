//
//  AudioMiniPlayerShape.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

enum AudioMiniPlayerShape {

    /// Outline of the two-row music card: a rounded rectangle whose bottom
    /// corners follow the round buttons (and the Music circle nested in the
    /// trailing corner), with gentler corners on top above the song name.
    ///
    /// The shape is symmetric, so it needs no mirroring for right-to-left.
    static func maskPath(
        in rect: CGRect,
        topRadius: CGFloat,
        bottomRadius: CGFloat
    ) -> UIBezierPath {
        let limit = max(0, min(rect.width, rect.height) / 2)
        let top = min(max(topRadius, 0), limit)
        let bottom = min(max(bottomRadius, 0), limit)
        let path = UIBezierPath()
        path.move(to: CGPoint(x: rect.minX + top, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY))
        path.addArc(
            withCenter: CGPoint(x: rect.maxX - top, y: rect.minY + top),
            radius: top, startAngle: -.pi / 2, endAngle: 0, clockwise: true
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottom))
        path.addArc(
            withCenter: CGPoint(x: rect.maxX - bottom, y: rect.maxY - bottom),
            radius: bottom, startAngle: 0, endAngle: .pi / 2, clockwise: true
        )
        path.addLine(to: CGPoint(x: rect.minX + bottom, y: rect.maxY))
        path.addArc(
            withCenter: CGPoint(x: rect.minX + bottom, y: rect.maxY - bottom),
            radius: bottom, startAngle: .pi / 2, endAngle: .pi, clockwise: true
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + top))
        path.addArc(
            withCenter: CGPoint(x: rect.minX + top, y: rect.minY + top),
            radius: top, startAngle: .pi, endAngle: -.pi / 2, clockwise: true
        )
        path.close()
        return path
    }
}
