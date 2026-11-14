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

    private static var cache: [UUID: (backdrop: ObjectIdentifier?, image: UIImage)] = [:]

    /// The composite for `frameId` over `backdrop`, or nil if the frame is gone.
    static func image(frameId: UUID, backdrop: UIImage?) -> UIImage? {
        let key = backdrop.map(ObjectIdentifier.init)
        if let hit = cache[frameId], hit.backdrop == key {
            return hit.image
        }
        guard let frame = CameraFrameStore.shared.image(for: frameId) else { return nil }
        let image = compose(frame: frame, backdrop: backdrop)
        cache[frameId] = (key, image)
        return image
    }

    /// Drops cached composites (frames were rotated, replaced or removed).
    static func invalidate() {
        cache.removeAll()
    }

    /// Draws `backdrop` aspect-filled under `frame`, at the frame's shape.
    static func compose(frame: UIImage, backdrop: UIImage?) -> UIImage {
        let source = frame.size
        guard source.width > 0, source.height > 0 else { return frame }
        let scale = min(1, maxSide / max(source.width, source.height))
        let size = CGSize(width: source.width * scale, height: source.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.mediaPlaceholder.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            if let backdrop, backdrop.size.width > 0, backdrop.size.height > 0 {
                let fill = max(
                    size.width / backdrop.size.width,
                    size.height / backdrop.size.height
                )
                let drawn = CGSize(
                    width: backdrop.size.width * fill,
                    height: backdrop.size.height * fill
                )
                backdrop.draw(in: CGRect(
                    x: (size.width - drawn.width) / 2,
                    y: (size.height - drawn.height) / 2,
                    width: drawn.width,
                    height: drawn.height
                ))
            }
            frame.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
