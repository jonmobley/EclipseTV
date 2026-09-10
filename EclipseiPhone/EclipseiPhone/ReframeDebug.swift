//
//  ReframeDebug.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import os
import UIKit

/// Temporary instrumentation for the thin-crop bug. Leave on until the mapping
/// that matches the white box is identified, then delete this file.
enum ReframeDebug {
    static let isEnabled = true
    static let logger = Logger(subsystem: "com.eclipseapp.ios", category: "Reframe")
    /// Item the user is editing; `framedStill` logs when it matches.
    static var watchedId: String?
}

extension ReframeDebug {

    /// Live HUD under the crop window: three independent mappings plus the saved rect.
    static func hudText(on controller: AspectCropViewController) -> String {
        Snapshot(controller: controller, saved: controller.visibleCropRectInImage()).hud
    }

    /// Full dump for the Xcode console and the pasteboard.
    static func dump(on controller: AspectCropViewController, saved: CGRect) -> String {
        Snapshot(controller: controller, saved: saved).full
    }

    /// Short dump for the Save confirmation alert.
    static func alertText(on controller: AspectCropViewController, saved: CGRect) -> String {
        Snapshot(controller: controller, saved: saved).alert
    }

    /// Logs the full photo versus the tile bitmap when Edit opens.
    static func logOpening(itemId: String, full: UIImage, thumbnail: UIImage?) {
        watchedId = itemId
        let stored = MediaFramingStore.framing(forId: itemId)
        let storedText = stored.map {
            "\(fmt($0.x)),\(fmt($0.y)) \(fmt($0.width))×\(fmt($0.height))"
        } ?? "none"
        let vertical = ExternalOutputSettings.isVerticalMode
        let text = """
        [Reframe] OPEN id=\(itemId)
          full  \(describe(full))
          thumb \(thumbnail.map(describe) ?? "nil")
          stored \(storedText)
          target \(fmt(MediaAspect.activeTarget)) vertical=\(vertical)
        """
        print(text)
        logger.error("\(text, privacy: .public)")
    }

    /// Logs the unit rect written to disk and the crop it would produce on the tile.
    static func logApplied(framing: MediaFraming, itemId: String, thumbnail: UIImage?) {
        let crop = thumbnail.map { framing.rect(in: $0.size) }
        let result: UIImage?
        if let thumbnail, let crop {
            result = MediaAspect.crop(thumbnail, to: crop)
        } else {
            result = nil
        }
        let text = """
        [Reframe] APPLY id=\(itemId)
          unit \(fmt(framing.x)),\(fmt(framing.y)) \(fmt(framing.width))×\(fmt(framing.height))
          thumb \(thumbnail.map(describe) ?? "nil")
          cropPt \(crop.map(rect) ?? "nil")
          result \(result.map(describe) ?? "nil — crop failed or no thumb")
        """
        print(text)
        logger.error("\(text, privacy: .public)")
    }

    /// Logs the tile's crop of the watched item only, so grid reload isn't noisy.
    static func logFramedStill(
        id: String,
        source: UIImage,
        framing: MediaFraming,
        crop: CGRect,
        result: UIImage
    ) {
        guard id == watchedId else { return }
        let text = """
        [Reframe] TILE id=\(id)
          source \(describe(source))
          unit \(fmt(framing.x)),\(fmt(framing.y)) \(fmt(framing.width))×\(fmt(framing.height))
          cropPt \(rect(crop))
          result \(describe(result))
        """
        print(text)
        logger.error("\(text, privacy: .public)")
    }
}
