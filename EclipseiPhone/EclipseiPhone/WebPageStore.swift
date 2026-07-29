//
//  WebPageStore.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import os.log

/// Persists saved web pages as lightweight JSON metadata in UserDefaults.
@MainActor
final class WebPageStore {

    static let shared = WebPageStore()

    /// Posted when the saved pages list changes.
    static let didChangeNotification = Notification.Name("WebPageStore.didChange")

    /// Normalization / validation failures when adding a page.
    enum StoreError: LocalizedError {
        case emptyTitle
        case invalidURL
        case httpsRequired

        var errorDescription: String? {
            switch self {
            case .emptyTitle: return "Enter a title for this page."
            case .invalidURL: return "That doesn't look like a valid web address."
            case .httpsRequired: return "Only HTTPS pages can be displayed."
            }
        }
    }

    private(set) var pages: [WebPage] = []

    /// True when the stored payload could not be read on launch. The undecodable bytes
    /// are preserved under `backupKey` so the pages are recoverable rather than lost.
    private(set) var didFailToLoad = false

    private let defaults: UserDefaults
    private let itemsKey = "EclipseTV.pages.items"
    private let backupKey = "EclipseTV.pages.items.unreadableBackup"
    private let logger = Logger(subsystem: "com.eclipseapp.ios", category: "WebPageStore")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: - Mutations

    /// Adds a page after normalizing and validating the URL. Throws `StoreError` on failure.
    @discardableResult
    func add(title: String, urlString: String) throws -> WebPage {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { throw StoreError.emptyTitle }
        let url = try Self.normalizedHTTPSURL(from: urlString)
        let page = WebPage(title: trimmedTitle, url: url)
        pages.insert(page, at: 0)
        persist()
        WarmWebSessionPool.shared.warmIfNeeded(for: page)
        return page
    }

    /// Removes the page with `id` if present.
    func remove(id: UUID) {
        let before = pages.count
        pages.removeAll { $0.id == id }
        guard pages.count != before else { return }
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

    private func load() {
        guard let data = defaults.data(forKey: itemsKey) else { return }

        if let decoded = try? JSONDecoder().decode([WebPage].self, from: data) {
            pages = decoded
            return
        }

        // Salvage whatever individual entries still decode before giving up.
        if let salvaged = try? JSONDecoder().decode([SalvagedPage].self, from: data) {
            pages = salvaged.compactMap(\.page)
            logger.error("Recovered \(self.pages.count) of \(salvaged.count) saved pages")
            if pages.count != salvaged.count {
                defaults.set(data, forKey: backupKey)
            }
            return
        }

        // Container itself is unreadable. Keep the bytes so the pages can be recovered,
        // and start empty rather than writing over them.
        logger.error("Saved pages payload is unreadable; preserving a backup copy")
        defaults.set(data, forKey: backupKey)
        pages = []
        didFailToLoad = true
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(pages)
            defaults.set(data, forKey: itemsKey)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        } catch {
            logger.error("Failed to encode saved pages: \(error.localizedDescription)")
        }
    }
}
