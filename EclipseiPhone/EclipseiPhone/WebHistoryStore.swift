//
//  WebHistoryStore.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// One page the phone browser finished loading.
struct WebHistoryEntry: Codable, Equatable {
    let url: URL
    var title: String
    var visitedAt: Date
}

/// Recent pages for the browser's history drawer: newest first, one row per address,
/// kept on this phone only (never synced or sent anywhere).
@MainActor
final class WebHistoryStore {

    static let shared = WebHistoryStore()

    /// Oldest pages fall off past this many.
    static let limit = 30
    static let storageKey = "EclipseTV.web.recentPages"

    private let defaults: UserDefaults
    private(set) var entries: [WebHistoryEntry]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([WebHistoryEntry].self, from: data) {
            entries = saved
        } else {
            entries = []
        }
    }

    /// Puts `url` at the top. A page already listed moves up and takes the new title.
    func record(url: URL, title: String?, at date: Date = Date()) {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return
        }
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = trimmed.isEmpty ? Self.fallbackTitle(for: url) : trimmed
        entries.removeAll { Self.sameAddress($0.url, url) }
        entries.insert(WebHistoryEntry(url: url, title: name, visitedAt: date), at: 0)
        if entries.count > Self.limit {
            entries.removeLast(entries.count - Self.limit)
        }
        save()
    }

    func clear() {
        entries = []
        defaults.removeObject(forKey: Self.storageKey)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    /// Host without `www.`, for pages with no title.
    static func fallbackTitle(for url: URL) -> String {
        guard let host = url.host, !host.isEmpty else { return url.absoluteString }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Same page, ignoring a trailing `#fragment`.
    static func sameAddress(_ a: URL, _ b: URL) -> Bool {
        var ca = URLComponents(url: a, resolvingAgainstBaseURL: false)
        var cb = URLComponents(url: b, resolvingAgainstBaseURL: false)
        ca?.fragment = nil
        cb?.fragment = nil
        return ca?.url == cb?.url
    }
}
