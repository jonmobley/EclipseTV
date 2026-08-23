//
//  LocalAlbum.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// A user-created on-device album that groups media by library item id.
struct LocalAlbum: Codable, Equatable, Identifiable, Hashable {
    let id: UUID
    var name: String
    /// Media ids (`LibraryItemDTO.id`), website ids (`WebPage.id.uuidString`),
    /// and PDF ids (`SavedPDF.id.uuidString`) in membership order (cover / sync).
    /// Tools never appear here.
    var itemIds: [String]
    /// Preferred cover media id; falls back to the first item when nil/missing.
    var coverId: String?
    /// Display Mode this album belongs to (home grid + media bucket).
    var orientation: ExternalOutputOrientation
    let createdAt: Date
    /// Last time the user opened this Show; drives Home “Last opened …” copy.
    var lastOpenedAt: Date?
    /// Ordered Show grid: tool tokens, member ids, and slideshow tokens.
    /// `nil` = default tools, then members, then slideshows.
    var surfaceIds: [String]?
    /// Practice Mode: live preview plus Lock / Blackout with no AirPlay, HDMI,
    /// or EclipseTV. Default is off; taps then open on-device Preview instead.
    var previewsWhenDisconnected: Bool

    /// Creates an empty album with `name` in `orientation`.
    init(
        id: UUID = UUID(),
        name: String,
        itemIds: [String] = [],
        coverId: String? = nil,
        orientation: ExternalOutputOrientation = .landscape,
        createdAt: Date = Date(),
        lastOpenedAt: Date? = nil,
        surfaceIds: [String]? = nil,
        previewsWhenDisconnected: Bool = false
    ) {
        self.id = id
        self.name = name
        self.itemIds = itemIds
        self.coverId = coverId
        self.orientation = orientation
        self.createdAt = createdAt
        self.lastOpenedAt = lastOpenedAt
        self.surfaceIds = surfaceIds
        self.previewsWhenDisconnected = previewsWhenDisconnected
    }

    /// Effective cover id for thumbnail display.
    var resolvedCoverId: String? {
        if let coverId, itemIds.contains(coverId) { return coverId }
        return itemIds.first
    }

    /// Grid order for this Show (tools + members). Slideshow tokens already on
    /// `surfaceIds` are kept; missing slideshows are not invented here.
    var resolvedSurfaceIds: [String] {
        resolvedSurfaceIds(slideshowIds: nil)
    }

    /// Grid order including `slideshowIds` (appended when not already on the surface).
    func resolvedSurfaceIds(slideshowIds: [String]?) -> [String] {
        Self.sanitizedSurface(
            surfaceIds ?? (ShowToolToken.all + itemIds),
            itemIds: itemIds,
            slideshowIds: slideshowIds
        )
    }

    /// Tool tokens not currently on the surface (for the + menu restore section).
    var missingToolTokens: [String] {
        let present = Set(resolvedSurfaceIds.filter(ShowToolToken.isTool))
        return ShowToolToken.all.filter { !present.contains($0) }
    }

    /// Drops unknown tools and stale members; appends missing members / slideshows.
    ///
    /// When `slideshowIds` is nil, slideshow tokens already on `surface` are kept
    /// but none are appended. When non-nil, only those tokens are kept, then
    /// any missing ones are appended (new slideshows land after tools/media).
    static func sanitizedSurface(
        _ surface: [String],
        itemIds: [String],
        slideshowIds: [String]? = nil
    ) -> [String] {
        let memberSet = Set(itemIds)
        let slideshowSet = slideshowIds.map(Set.init)
        var seen = Set<String>()
        var result: [String] = []
        for id in surface {
            guard shouldKeepSurfaceId(
                id, members: memberSet, slideshows: slideshowSet
            ), seen.insert(id).inserted else { continue }
            result.append(id)
        }
        for id in itemIds where seen.insert(id).inserted {
            result.append(id)
        }
        if let slideshowIds {
            for id in slideshowIds where seen.insert(id).inserted {
                result.append(id)
            }
        }
        return result
    }

    private static func shouldKeepSurfaceId(
        _ id: String,
        members: Set<String>,
        slideshows: Set<String>?
    ) -> Bool {
        if ShowToolToken.isTool(id) { return true }
        if members.contains(id) { return true }
        guard ShowSlideshowToken.isSlideshow(id) else { return false }
        if let slideshows { return slideshows.contains(id) }
        return true
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id, name, itemIds, coverId, orientation, createdAt, lastOpenedAt, surfaceIds
        case previewsWhenDisconnected
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        itemIds = try c.decode([String].self, forKey: .itemIds)
        coverId = try c.decodeIfPresent(String.self, forKey: .coverId)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        lastOpenedAt = try c.decodeIfPresent(Date.self, forKey: .lastOpenedAt)
        surfaceIds = try c.decodeIfPresent([String].self, forKey: .surfaceIds)
        previewsWhenDisconnected = try c.decodeIfPresent(
            Bool.self, forKey: .previewsWhenDisconnected
        ) ?? false
        // Pre-mode albums land in Landscape (app default).
        let raw = try c.decodeIfPresent(String.self, forKey: .orientation)
        orientation = ExternalOutputOrientation.resolved(fromStored: raw)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(itemIds, forKey: .itemIds)
        try c.encodeIfPresent(coverId, forKey: .coverId)
        try c.encode(orientation.rawValue, forKey: .orientation)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(lastOpenedAt, forKey: .lastOpenedAt)
        try c.encodeIfPresent(surfaceIds, forKey: .surfaceIds)
        try c.encode(previewsWhenDisconnected, forKey: .previewsWhenDisconnected)
    }

    /// Compact relative open time for Home tiles and Show lists (`3hrs ago`).
    var lastOpenedSubtitle: String {
        Self.compactRelativeOpenString(for: lastOpenedAt ?? createdAt)
    }

    /// Formats `date` as a short relative string for Home/Show lists.
    static func compactRelativeOpenString(
        for date: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let interval = max(0, now.timeIntervalSince(date))
        if interval < 60 { return "Just now" }

        if calendar.isDateInYesterday(date) { return "Yesterday" }

        if calendar.isDate(date, inSameDayAs: now) || interval < 24 * 3600 {
            let hours = Int(interval / 3600)
            if hours < 1 {
                let minutes = max(1, Int(interval / 60))
                return minutes == 1 ? "1min ago" : "\(minutes)mins ago"
            }
            return hours == 1 ? "1hr ago" : "\(hours)hrs ago"
        }

        let days = calendar.dateComponents([.day], from: date, to: now).day ?? 0
        if days < 7 {
            return days <= 1 ? "1 day ago" : "\(days) days ago"
        }

        let weeks = days / 7
        if weeks < 5 {
            return weeks == 1 ? "1 week ago" : "\(weeks) weeks ago"
        }

        let months = calendar.dateComponents([.month], from: date, to: now).month ?? 0
        if months < 12 {
            return months <= 1 ? "1 month ago" : "\(months) months ago"
        }

        let years = max(1, calendar.dateComponents([.year], from: date, to: now).year ?? 1)
        return years == 1 ? "1 year ago" : "\(years) years ago"
    }
}
