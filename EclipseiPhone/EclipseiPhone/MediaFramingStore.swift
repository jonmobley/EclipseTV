//
//  MediaFramingStore.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Normalized crop rectangle for a still (unit space, origin top-left).
///
/// Saved when the user drags/pinches in the framing editor. Applied by cropping the
/// bitmap to this region and showing the result aspect-fit, so the original file is
/// never rewritten.
struct MediaFraming: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    /// Point-space crop inside an image of `imageSize` (top-left origin).
    func rect(in imageSize: CGSize) -> CGRect {
        CGRect(
            x: x * imageSize.width,
            y: y * imageSize.height,
            width: width * imageSize.width,
            height: height * imageSize.height
        )
    }

    /// Builds unit-space framing from a point-space crop in an image of `imageSize`.
    init(rect: CGRect, in imageSize: CGSize) {
        guard imageSize.width > 0, imageSize.height > 0 else {
            self.x = 0
            self.y = 0
            self.width = 1
            self.height = 1
            return
        }
        self.x = rect.origin.x / imageSize.width
        self.y = rect.origin.y / imageSize.height
        self.width = rect.width / imageSize.width
        self.height = rect.height / imageSize.height
    }

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// Four doubles for UserDefaults / wire plist storage.
    var asArray: [Double] { [x, y, width, height] }

    /// Wire DTO for Multipeer control envelopes.
    var asDTO: MediaFramingDTO {
        MediaFramingDTO(x: x, y: y, width: width, height: height)
    }

    /// Restores from a four-double array; nil when the shape is wrong.
    static func fromArray(_ values: [Double]) -> MediaFraming? {
        guard values.count == 4,
              values[2] > 0, values[3] > 0 else { return nil }
        return MediaFraming(x: values[0], y: values[1], width: values[2], height: values[3])
    }

    /// Restores from a wire DTO.
    static func fromDTO(_ dto: MediaFramingDTO) -> MediaFraming {
        MediaFraming(x: dto.x, y: dto.y, width: dto.width, height: dto.height)
    }
}

/// Per-item custom crop position for stills, alongside Fit / Fill.
///
/// Stored as `[itemId: [x, y, width, height]]` in UserDefaults. Items without an
/// entry use Fit / Fill only; the map only holds stills the user positioned by hand.
enum MediaFramingStore {
    private static let key = "EclipseTV.media.framing"

    /// Saved framing for `id`, or nil when the item uses Fit / Fill only.
    static func framing(forId id: String) -> MediaFraming? {
        guard let values = stored()[id] else { return nil }
        return MediaFraming.fromArray(values)
    }

    /// Whether `id` has a custom position (Screen Fit → Custom).
    static func hasFraming(forId id: String) -> Bool {
        framing(forId: id) != nil
    }

    static func set(_ framing: MediaFraming, forId id: String) {
        var map = stored()
        map[id] = framing.asArray
        UserDefaults.standard.set(map, forKey: key)
    }

    /// Drops a custom position so Fit / Fill take over again.
    static func clear(forId id: String) {
        var map = stored()
        guard map.removeValue(forKey: id) != nil else { return }
        UserDefaults.standard.set(map, forKey: key)
    }

    /// Crops `image` to the saved framing when present; otherwise returns it unchanged.
    ///
    /// Custom framing always pairs with `.scaleAspectFit` because the crop is already
    /// locked to the display aspect. Without framing, `fallback` (Fit / Fill) is used.
    static func framedStill(
        _ image: UIImage?,
        forId id: String,
        fallback: UIView.ContentMode
    ) -> (image: UIImage?, contentMode: UIView.ContentMode) {
        guard let image,
              let framing = framing(forId: id) else {
            return (image, fallback)
        }
        let crop = framing.rect(in: image.size)
        let cropped = MediaAspect.crop(image, to: crop) ?? image
        return (cropped, .scaleAspectFit)
    }

    private static func stored() -> [String: [Double]] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: [Double]] ?? [:]
    }
}
