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

    private let defaults: UserDefaults
    private let itemsKey = "EclipseTV.pages.items"
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
        WebThumbnailPrefetcher.shared.enqueue([page])
        return page
    }

    /// Removes the page with `id` if present.
    func remove(id: UUID) {
        let before = pages.count
        pages.removeAll { $0.id == id }
        guard pages.count != before else { return }
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

    private func load() {
        guard let data = defaults.data(forKey: itemsKey) else { return }
        do {
            pages = try JSONDecoder().decode([WebPage].self, from: data)
        } catch {
            logger.error("Failed to decode saved pages: \(error.localizedDescription)")
            pages = []
        }
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
