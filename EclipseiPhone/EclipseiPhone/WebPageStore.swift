//
//  WebPageStore.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import os.log

/// Persists the global website history library as JSON metadata in UserDefaults.
///
/// `pages` is the History list shared across Shows. Pages removed from that list
/// but still referenced by a Show are kept in `retainedPages` so membership is
/// independent of the convenience list.
@MainActor
final class WebPageStore {

    static let shared = WebPageStore()

    /// Posted when the saved pages list changes.
    static let didChangeNotification = Notification.Name("WebPageStore.didChange")

    /// Normalization / validation failures when adding a page.
    enum StoreError: LocalizedError {
        case invalidURL
        case httpsRequired

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "That doesn't look like a valid web address."
            case .httpsRequired: return "Only HTTPS pages can be displayed."
            }
        }
    }

    /// Global History list (compose suggestions + History screen).
    private(set) var pages: [WebPage] = []
    /// Pages dropped from the list but still needed by one or more Shows.
    private(set) var retainedPages: [WebPage] = []

    /// True when the stored payload could not be read on launch. The undecodable bytes
    /// are preserved under `backupKey` so the pages are recoverable rather than lost.
    private(set) var didFailToLoad = false

    private let defaults: UserDefaults
    private let itemsKey = "EclipseTV.pages.items"
    private let retainedKey = "EclipseTV.pages.retained"
    private let backupKey = "EclipseTV.pages.items.unreadableBackup"
    private let logger = Logger(subsystem: "com.eclipseapp.ios", category: "WebPageStore")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: - Lookup

    /// List page or Show-retained page with `id`, if any.
    func page(id: UUID) -> WebPage? {
        pages.first { $0.id == id } ?? retainedPages.first { $0.id == id }
    }

    /// Every page id that must survive library prune (list + Show-retained).
    var keepIds: Set<String> {
        Set(pages.map { $0.id.uuidString } + retainedPages.map { $0.id.uuidString })
    }

    // MARK: - Mutations

    /// Adds a page after normalizing and validating the URL. Throws `StoreError` on failure.
    ///
    /// When `title` is blank, the URL host becomes the display title so Add never fails
    /// just because the optional name field was left empty.
    @discardableResult
    func add(title: String, urlString: String) throws -> WebPage {
        let url = try Self.normalizedHTTPSURL(from: urlString)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = UserDisplayName.clamp(
            trimmedTitle.isEmpty ? (url.host ?? url.absoluteString) : trimmedTitle
        )
        let page = WebPage(title: resolvedTitle, url: url)
        pages.insert(page, at: 0)
        retainedPages.removeAll { $0.id == page.id }
        persist()
        WarmWebSessionPool.shared.warmIfNeeded(for: page)
        return page
    }

    /// Reuses an existing page with the same HTTPS URL when possible; otherwise adds.
    ///
    /// Keeps one warm session / thumbnail per address when re-adding to a Show.
    @discardableResult
    func addOrReuse(title: String, urlString: String) throws -> WebPage {
        let url = try Self.normalizedHTTPSURL(from: urlString)
        if let existing = page(matching: url) {
            touch(existing.id)
            return page(id: existing.id) ?? existing
        }
        return try add(title: title, urlString: urlString)
    }

    /// List or retained page whose URL matches `url` (absolute string).
    func page(matching url: URL) -> WebPage? {
        let key = url.absoluteString
        return pages.first { $0.url.absoluteString == key }
            ?? retainedPages.first { $0.url.absoluteString == key }
    }

    /// Recent pages matching `query` in title or host (case-insensitive).
    ///
    /// Empty query returns the most recent pages. When `excludingShowId` is set,
    /// pages already on that Show are omitted.
    func suggestions(
        matching query: String,
        excludingShowId: UUID? = nil,
        limit: Int = 8
    ) -> [WebPage] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let memberIds: Set<String> = {
            guard let excludingShowId,
                  let album = LocalAlbumStore.shared.album(id: excludingShowId)
            else { return [] }
            return Set(album.itemIds)
        }()
        let pool = pages + retainedPages.filter { retained in
            !pages.contains(where: { $0.id == retained.id })
        }
        var seen = Set<UUID>()
        var matches: [WebPage] = []
        for page in pool {
            if seen.contains(page.id) { continue }
            if memberIds.contains(page.id.uuidString) { continue }
            if !needle.isEmpty {
                let title = page.title.lowercased()
                let host = (page.url.host ?? "").lowercased()
                let absolute = page.url.absoluteString.lowercased()
                guard title.contains(needle)
                        || host.contains(needle)
                        || absolute.contains(needle) else { continue }
            }
            seen.insert(page.id)
            matches.append(page)
            if matches.count >= limit { break }
        }
        return matches
    }

    /// Moves `id` to the front of History (and restores it from retained if needed).
    func touch(_ id: UUID) {
        if let index = pages.firstIndex(where: { $0.id == id }) {
            let page = pages.remove(at: index)
            pages.insert(page, at: 0)
            persist()
            return
        }
        guard let retained = retainedPages.first(where: { $0.id == id }) else { return }
        retainedPages.removeAll { $0.id == id }
        pages.insert(retained, at: 0)
        persist()
        WarmWebSessionPool.shared.warmIfNeeded(for: retained)
    }

    /// Removes the page from the History list.
    ///
    /// Show membership is left alone. If any Show still references the page, its
    /// metadata is retained so the Show tile keeps working; otherwise assets are cleared.
    func remove(id: UUID) {
        guard let index = pages.firstIndex(where: { $0.id == id }) else { return }
        let page = pages.remove(at: index)
        if isReferencedByAnyShow(id: id) {
            if !retainedPages.contains(where: { $0.id == id }) {
                retainedPages.append(page)
            }
        } else {
            retainedPages.removeAll { $0.id == id }
            WarmWebSessionPool.shared.remove(pageId: id)
            WebThumbnailStore.shared.remove(id: id)
        }
        persist()
    }

    /// Drops Show-retained metadata when no Show still references `id`.
    func purgeRetainedIfUnused(id: UUID) {
        guard retainedPages.contains(where: { $0.id == id }) else { return }
        guard !isReferencedByAnyShow(id: id) else { return }
        retainedPages.removeAll { $0.id == id }
        WarmWebSessionPool.shared.remove(pageId: id)
        WebThumbnailStore.shared.remove(id: id)
        persist()
    }

    // MARK: - URL Normalization

    /// Prepends `https://` when no scheme is given; requires a resolvable HTTPS URL.
    static func normalizedHTTPSURL(from raw: String) throws -> URL {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw StoreError.invalidURL }

        if !trimmed.contains("://") {
            trimmed = "https://\(trimmed)"
        }

        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              let host = url.host, !host.isEmpty else {
            throw StoreError.invalidURL
        }

        guard scheme == "https" else { throw StoreError.httpsRequired }
        return url
    }

    // MARK: - Persistence

    /// Decodes one element without failing its whole container.
    ///
    /// Lets a single malformed or future-schema entry be dropped instead of taking every
    /// saved page with it — the previous behaviour reset `pages` to empty, and the next
    /// write then destroyed the user's bookmarks permanently.
    private struct SalvagedPage: Decodable {
        let page: WebPage?

        init(from decoder: Decoder) throws {
            page = try? WebPage(from: decoder)
        }
    }

    private func isReferencedByAnyShow(id: UUID) -> Bool {
        let key = id.uuidString
        return LocalAlbumStore.shared.albums.contains { $0.itemIds.contains(key) }
    }

    private func load() {
        pages = decodePages(forKey: itemsKey, isPrimaryList: true)
        retainedPages = decodePages(forKey: retainedKey, isPrimaryList: false)
    }

    private func decodePages(forKey key: String, isPrimaryList: Bool) -> [WebPage] {
        guard let data = defaults.data(forKey: key) else { return [] }

        if let decoded = try? JSONDecoder().decode([WebPage].self, from: data) {
            return decoded
        }

        if let salvaged = try? JSONDecoder().decode([SalvagedPage].self, from: data) {
            let pages = salvaged.compactMap(\.page)
            logger.error("Recovered \(pages.count) of \(salvaged.count) pages for \(key)")
            if pages.count != salvaged.count, isPrimaryList {
                defaults.set(data, forKey: backupKey)
            }
            return pages
        }

        if isPrimaryList {
            logger.error("Saved pages payload is unreadable; preserving a backup copy")
            defaults.set(data, forKey: backupKey)
            didFailToLoad = true
        } else {
            logger.error("Retained pages payload is unreadable for \(key)")
        }
        return []
    }

    private func persist() {
        do {
            let listData = try JSONEncoder().encode(pages)
            defaults.set(listData, forKey: itemsKey)
            let retainedData = try JSONEncoder().encode(retainedPages)
            defaults.set(retainedData, forKey: retainedKey)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        } catch {
            logger.error("Failed to encode saved pages: \(error.localizedDescription)")
        }
    }
}
