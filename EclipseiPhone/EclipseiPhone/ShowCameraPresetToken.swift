//
//  ShowCameraPresetToken.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Surface ids for Camera Preset tiles: the phone camera with one saved frame.
///
/// A preset is only a pointer to a `CameraFrame`, so the token is the whole
/// record and it syncs with the Show's surface like any tool. It sits under
/// `ShowToolToken.prefix`, so builds that predate presets keep it through sync.
enum ShowCameraPresetToken {
    static let prefix = ShowToolToken.prefix + "cameraPreset."

    /// Surface id for a preset that shows the frame `frameId`.
    static func token(for frameId: UUID) -> String {
        prefix + frameId.uuidString
    }

    /// Whether `id` is a Camera Preset surface token.
    static func isCameraPreset(_ id: String) -> Bool {
        id.hasPrefix(prefix)
    }

    /// Frame UUID encoded in `token`, if it is a valid preset surface id.
    static func frameId(from token: String) -> UUID? {
        guard isCameraPreset(token) else { return nil }
        return UUID(uuidString: String(token.dropFirst(prefix.count)))
    }

    /// Frame ids (uuid strings) of every preset on `surface`.
    static func frameIds(in surface: [String]) -> Set<String> {
        Set(surface.compactMap { frameId(from: $0)?.uuidString })
    }
}

/// Tile picture for a Camera Preset: the last camera picture with the frame on top.
///
/// The live feed has one preview layer and the Camera tile owns it, so presets
/// show a still. Composites are cached because grid cells reconfigure often.
@MainActor
enum CameraPresetThumbnail {

    /// Longest side of the composite; tiles are small.
    private static let maxSide: CGFloat = 640

    private struct CacheKey: Equatable {
        let backdrop: ObjectIdentifier?
        let aspect: CGFloat
    }

    private static var cache: [UUID: (key: CacheKey, image: UIImage)] = [:]

    /// The composite for `frameId` over `backdrop`, or nil if the frame is gone.
    static func image(frameId: UUID, backdrop: UIImage?) -> UIImage? {
        let aspect = ExternalOutputSettings.outputAspectRatio
        let key = CacheKey(backdrop: backdrop.map(ObjectIdentifier.init), aspect: aspect)
        if let hit = cache[frameId], hit.key == key {
            return hit.image
        }
        guard let frame = CameraFrameStore.shared.image(for: frameId) else { return nil }
        let image = compose(frame: frame, backdrop: backdrop, outputAspect: aspect)
        cache[frameId] = (key, image)
        return image
    }

    /// Drops cached composites (frames were rotated, replaced or removed).
    static func invalidate() {
        cache.removeAll()
    }

    /// Draws the picture the TV shows: an `outputAspect` panel with `backdrop`
    /// aspect-filled and `frame` aspect-fitted on top (same as the AirPlay overlay
    /// and the hero). Drawing at the frame's own shape stretched a frame that isn't
    /// the output's shape into a fill the TV never shows (2026-11-23).
    static func compose(frame: UIImage, backdrop: UIImage?, outputAspect: CGFloat) -> UIImage {
        guard outputAspect > 0 else { return frame }
        let size = outputAspect >= 1
            ? CGSize(width: maxSide, height: (maxSide / outputAspect).rounded())
            : CGSize(width: (maxSide * outputAspect).rounded(), height: maxSide)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.mediaPlaceholder.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            if let backdrop {
                backdrop.draw(in: placed(backdrop.size, in: size, fill: true))
            }
            frame.draw(in: placed(frame.size, in: size, fill: false))
        }
    }

    /// `content` scaled to fill or fit `canvas`, centred.
    private static func placed(_ content: CGSize, in canvas: CGSize, fill: Bool) -> CGRect {
        guard content.width > 0, content.height > 0 else { return .zero }
        let sx = canvas.width / content.width
        let sy = canvas.height / content.height
        let scale = fill ? max(sx, sy) : min(sx, sy)
        let w = content.width * scale
        let h = content.height * scale
        return CGRect(x: (canvas.width - w) / 2, y: (canvas.height - h) / 2, width: w, height: h)
    }
}
