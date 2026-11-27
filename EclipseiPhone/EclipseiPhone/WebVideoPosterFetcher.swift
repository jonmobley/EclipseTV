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
    /// Pages tried since launch. A link with no poster to find (dead address, `.m3u8`)
    /// would otherwise be fetched again on every scroll-driven `warmSoon` call.
    private var attemptedThisRun = Set<UUID>()

    /// Pages whose poster was saved by the current rules (centered crop, large Vimeo
    /// art, file stills; 2026-11-26). Posters saved before then are fetched once more.
    private static let currentPostersKey = "EclipseTV.webVideoPoster.v2Ids"
    private var currentPosterIds: Set<String>

    private init() {
        currentPosterIds = Set(
            UserDefaults.standard.stringArray(forKey: Self.currentPostersKey) ?? []
        )
    }

    /// Fetches a poster when the bookmark is a video link and has no up-to-date poster yet.
    func fetchIfNeeded(for page: WebPage) {
        guard let link = page.videoLink else { return }
        guard WebThumbnailStore.shared.snapshot(for: page.id) == nil
                || !currentPosterIds.contains(page.id.uuidString)
        else { return }
        guard !inFlight.contains(page.id), !attemptedThisRun.contains(page.id) else { return }
        inFlight.insert(page.id)
        attemptedThisRun.insert(page.id)

        Task { [weak self] in
            defer { Task { @MainActor in self?.inFlight.remove(page.id) } }
            switch link {
            case .youTube:
                await self?.fetchYouTubePoster(link: link, pageId: page.id)
            case .vimeo:
                await self?.fetchVimeoPoster(originalURL: page.url, pageId: page.id)
            case .directFile(let url):
                await self?.fetchFilePoster(url: url, pageId: page.id)
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
                savePoster(image, for: pageId)
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
        // Without `width` oEmbed hands back a 295×166 thumbnail, blurry on a tile.
        components?.queryItems = [
            URLQueryItem(name: "url", value: originalURL.absoluteString),
            URLQueryItem(name: "width", value: "1280")
        ]
        guard let oembedURL = components?.url else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: oembedURL)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let thumb = json["thumbnail_url"] as? String,
                  let thumbURL = URL(string: thumb),
                  let image = await downloadImage(from: thumbURL)
            else { return }
            savePoster(image, for: pageId)
        } catch {
            logger.error("Vimeo oEmbed failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// A still from a linked video file (`.mp4`, `.mov`…). These links never load in a
    /// web view, so before this they had no picture at all, only the placeholder icon.
    /// HLS playlists (`.m3u8`) can't be sampled this way, are skipped and keep the placeholder.
    private func fetchFilePoster(url: URL, pageId: UUID) async {
        guard Self.canSampleFile(url) else { return }
        let image = await Self.fileLimiter.run {
            await Self.poster(at: url, timeout: Self.filePosterTimeout)
        }
        guard let image else {
            logger.error("Video file poster failed for \(pageId.uuidString, privacy: .public)")
            return
        }
        savePoster(image, for: pageId)
    }

    /// One remote file at a time: each one is a network asset load plus several frame
    /// grabs, and library posters already share the decoder (`TVLibraryStore.posterLimiter`).
    private static let fileLimiter = AsyncLimiter(limit: 1)
    /// A slow or stalled server gives up rather than holding the only slot.
    private static let filePosterTimeout: TimeInterval = 20

    /// HLS playlists have no frames to grab, so they are not fetched at all.
    nonisolated static func canSampleFile(_ url: URL) -> Bool {
        (url.path as NSString).pathExtension.lowercased() != "m3u8"
    }

    /// `VideoPosterFrame.poster`, or nil once `timeout` seconds pass.
    nonisolated static func poster(at url: URL, timeout: TimeInterval) async -> UIImage? {
        await firstResult(timeout: timeout) { await VideoPosterFrame.poster(at: url) }
    }

    /// `work`'s result, or nil once `timeout` seconds pass; on timeout `work` is cancelled.
    ///
    /// Returns at the deadline whatever the loader does. A task group waits for every
    /// child, and on CI a cancelled remote asset load did not return, so the old
    /// group never finished (the iPhone job hung for hours). The work runs as its
    /// own task: on timeout it is cancelled (which stops `VideoPosterFrame`'s work as
    /// soon as AVFoundation allows) and left behind, and the limiter slot is freed.
    ///
    /// The deadline is a Dispatch timer, not a `Task.sleep`: under heavy load (CI runs
    /// the unit tests in parallel) the Swift task pool can be busy for a long time, and
    /// a sleeping deadline task then woke far too late.
    nonisolated static func firstResult(
        timeout: TimeInterval,
        work: @escaping @Sendable () async -> UIImage?
    ) async -> UIImage? {
        let race = FirstResult()
        let task = Task { await work() }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + max(timeout, 0)) {
            if race.finish(nil) { task.cancel() }
        }
        return await withCheckedContinuation { continuation in
            race.set(continuation)
            Task {
                race.finish(await task.value)
            }
        }
    }

    /// Resumes a continuation once, with whichever result arrives first.
    private final class FirstResult: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<UIImage?, Never>?
        private var pending: UIImage??

        func set(_ continuation: CheckedContinuation<UIImage?, Never>) {
            lock.lock()
            if let pending {
                lock.unlock()
                continuation.resume(returning: pending)
                return
            }
            self.continuation = continuation
            lock.unlock()
        }

        /// True when this call delivered the result (it came first).
        @discardableResult
        func finish(_ value: UIImage?) -> Bool {
            lock.lock()
            if pending != nil {
                lock.unlock()
                return false
            }
            pending = .some(value)
            let waiting = continuation
            continuation = nil
            lock.unlock()
            waiting?.resume(returning: value)
            return true
        }
    }

    private func savePoster(_ image: UIImage, for pageId: UUID) {
        WebThumbnailStore.shared.saveSnapshot(image, for: pageId, centered: true)
        currentPosterIds.insert(pageId.uuidString)
        UserDefaults.standard.set(Array(currentPosterIds), forKey: Self.currentPostersKey)
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
