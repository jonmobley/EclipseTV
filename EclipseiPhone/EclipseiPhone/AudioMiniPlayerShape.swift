//
//  AudioMiniPlayerShape.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Outline of the mini-player card where it meets the Music circle.
enum AudioMiniPlayerShape {

    /// Leading end is a semicircle the height of `rect`. The trailing end is cut
    /// on the Music circle's arc so the card and circle share one capsule silhouette.
    ///
    /// - Parameter biteOnRight: The circle sits on the trailing edge. Pass false
    ///   for right-to-left layout, where that edge is on the left.
    static func maskPath(in rect: CGRect, biteOnRight: Bool) -> UIBezierPath {
        let radius = rect.height / 2
        guard radius > 0, rect.width >= radius * 2 else {
            let fallback = min(max(radius, 0), rect.width / 2)
            return UIBezierPath(roundedRect: rect, cornerRadius: fallback)
        }
        let path = trailingBitePath(in: rect, radius: radius)
        guard biteOnRight else {
            mirrorHorizontally(path, midX: rect.midX)
            return path
        }
        return path
    }

    // MARK: - Private

    /// Capsule body with a concave semicircle removed from the right edge.
    private static func trailingBitePath(in rect: CGRect, radius: CGFloat) -> UIBezierPath {
        let path = UIBezierPath()
        let top = rect.minY
        let bottom = rect.maxY
        let right = rect.maxX
        let midY = rect.midY
        let capX = rect.minX + radius

        path.move(to: CGPoint(x: capX, y: top))
        path.addLine(to: CGPoint(x: right, y: top))
        path.addArc(
            withCenter: CGPoint(x: right, y: midY),
            radius: radius,
            startAngle: -.pi / 2,
            endAngle: .pi / 2,
            clockwise: false
        )
        path.addLine(to: CGPoint(x: capX, y: bottom))
        path.addArc(
            withCenter: CGPoint(x: capX, y: midY),
            radius: radius,
            startAngle: .pi / 2,
            endAngle: -.pi / 2,
            clockwise: true
        )
        path.close()
        return path
    }

    /// Reflects `path` across the vertical line `x = midX`.
    private static func mirrorHorizontally(_ path: UIBezierPath, midX: CGFloat) {
        path.apply(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: midX * 2, ty: 0))
    }
}
