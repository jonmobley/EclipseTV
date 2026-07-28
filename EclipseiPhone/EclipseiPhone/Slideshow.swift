//
//  Slideshow.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Allowed Autoplay intervals (seconds) when Autoplay is on.
enum SlideshowAutoplaySeconds: Int, Codable, CaseIterable {
    case three = 3
    case five = 5
    case ten = 10
    case fifteen = 15

    /// Default dropdown value when Autoplay is later enabled.
    static let `default`: SlideshowAutoplaySeconds = .five

    /// Short label for settings UI.
    var label: String { "\(rawValue) sec" }
}

/// A named, ordered set of image library ids presented as one Show-grid thumbnail.
struct Slideshow: Codable, Equatable, Identifiable, Hashable {
    let id: UUID
    /// Show (`LocalAlbum`) this slideshow belongs to.
    var showId: UUID
    var name: String
    /// Image media ids (`LibraryItemDTO.id`) in play order.
    var itemIds: [String]
    /// Preferred cover media id; falls back to the first item when nil/missing.
    var coverId: String?
    /// Display Mode bucket (matches parent Show).
    var orientation: ExternalOutputOrientation
    /// When true, advances slides on a timer.
    var autoplay: Bool
    /// Interval used while `autoplay` is true.
    var autoplaySeconds: SlideshowAutoplaySeconds
    /// When true and `autoplay` is on, restarts after the last slide.
    var loop: Bool
    /// When true, uses Crossfade between slides (else Cut) for this run only.
    var crossfade: Bool
    /// When true, shows a slide ribbon on the phone while this slideshow is live.
    var showRibbonWhenLive: Bool
    let createdAt: Date

    /// Creates a slideshow with defaults (Autoplay / Loop / Crossfade / ribbon off).
    init(
        id: UUID = UUID(),
        showId: UUID,
        name: String,
        itemIds: [String] = [],
        coverId: String? = nil,
        orientation: ExternalOutputOrientation = ExternalOutputSettings.orientation,
        autoplay: Bool = false,
        autoplaySeconds: SlideshowAutoplaySeconds = .default,
        loop: Bool = false,
        crossfade: Bool = false,
        showRibbonWhenLive: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.showId = showId
        self.name = name
        self.itemIds = itemIds
        self.coverId = coverId
        self.orientation = orientation
        self.autoplay = autoplay
        self.autoplaySeconds = autoplaySeconds
        self.loop = loop
        self.crossfade = crossfade
        self.showRibbonWhenLive = showRibbonWhenLive
        self.createdAt = createdAt
    }

    /// Effective cover id for thumbnail display.
    var resolvedCoverId: String? {
        if let coverId, itemIds.contains(coverId) { return coverId }
        return itemIds.first
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id, showId, name, itemIds, coverId, orientation
        case autoplay, autoplaySeconds, loop, crossfade, showRibbonWhenLive, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        showId = try c.decode(UUID.self, forKey: .showId)
        name = try c.decode(String.self, forKey: .name)
        itemIds = try c.decode([String].self, forKey: .itemIds)
        coverId = try c.decodeIfPresent(String.self, forKey: .coverId)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        autoplay = try c.decodeIfPresent(Bool.self, forKey: .autoplay) ?? false
        autoplaySeconds = try c.decodeIfPresent(
            SlideshowAutoplaySeconds.self, forKey: .autoplaySeconds
        ) ?? .default
        loop = try c.decodeIfPresent(Bool.self, forKey: .loop) ?? false
        crossfade = try c.decodeIfPresent(Bool.self, forKey: .crossfade) ?? false
        showRibbonWhenLive = try c.decodeIfPresent(
            Bool.self, forKey: .showRibbonWhenLive
        ) ?? false
        let raw = try c.decodeIfPresent(String.self, forKey: .orientation)
        orientation = ExternalOutputOrientation.resolved(fromStored: raw)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(showId, forKey: .showId)
        try c.encode(name, forKey: .name)
        try c.encode(itemIds, forKey: .itemIds)
        try c.encodeIfPresent(coverId, forKey: .coverId)
        try c.encode(orientation.rawValue, forKey: .orientation)
        try c.encode(autoplay, forKey: .autoplay)
        try c.encode(autoplaySeconds, forKey: .autoplaySeconds)
        try c.encode(loop, forKey: .loop)
        try c.encode(crossfade, forKey: .crossfade)
        try c.encode(showRibbonWhenLive, forKey: .showRibbonWhenLive)
        try c.encode(createdAt, forKey: .createdAt)
    }
}
