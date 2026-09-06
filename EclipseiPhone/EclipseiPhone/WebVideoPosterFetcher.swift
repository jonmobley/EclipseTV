//
//  WebVideoPosterFetcher.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import os.log

/// Fills `WebThumbnailStore` with provider poster art for video-link bookmarks.
@MainActor
final class WebVideoPosterFetcher {

    static let shared = WebVideoPosterFetcher()

    private let logger = Logger(
        subsystem: "com.eclipseapp.ios", category: "WebVideoPoster"
    )
    private var inFlight = Set<UUID>()

    private init() {}

    /// Fetches a poster when the bookmark is a video link and has no snapshot yet.
    func fetchIfNeeded(for page: WebPage) {
        guard let link = page.videoLink else { return }
        guard WebThumbnailStore.shared.snapshot(for: page.id) == nil else { return }
        guard !inFlight.contains(page.id) else { return }
        inFlight.insert(page.id)

        Task { [weak self] in
            defer { Task { @MainActor in self?.inFlight.remove(page.id) } }
            switch link {
            case .youTube:
                await self?.fetchYouTubePoster(link: link, pageId: page.id)
            case .vimeo:
                await self?.fetchVimeoPoster(originalURL: page.url, pageId: page.id)
            case .directFile:
                break
            }
        }
    }

    /// Enqueues posters for every video-link page in History.
    func fetchAllSavedVideoPages() {
        for page in WebPageStore.shared.pages where page.videoLink != nil {
            fetchIfNeeded(for: page)
        }
    }

    // MARK: - Providers

    private func fetchYouTubePoster(link: WebVideoLink, pageId: UUID) async {
        let candidates = [link.posterURL, link.fallbackPosterURL].compactMap { $0 }
        for url in candidates {
            if let image = await downloadImage(from: url) {
                WebThumbnailStore.shared.saveSnapshot(image, for: pageId)
                return
            }
        }
        logger.error("YouTube poster fetch failed for \(pageId.uuidString, privacy: .public)")
    }

    private func fetchVimeoPoster(originalURL: URL, pageId: UUID) async {
        // oEmbed: https://vimeo.com/api/oembed.json?url=
        var components = URLComponents(
            string: "https://vimeo.com/api/oembed.json"
        )
        components?.queryItems = [
            URLQueryItem(name: "url", value: originalURL.absoluteString)
        ]
        guard let oembedURL = components?.url else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: oembedURL)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let thumb = json["thumbnail_url"] as? String,
                  let thumbURL = URL(string: thumb),
                  let image = await downloadImage(from: thumbURL)
            else { return }
            WebThumbnailStore.shared.saveSnapshot(image, for: pageId)
        } catch {
            logger.error("Vimeo oEmbed failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func downloadImage(from url: URL) async -> UIImage? {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                return nil
            }
            return UIImage(data: data)
        } catch {
            return nil
        }
    }
}
