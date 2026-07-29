//
//  WarmWebSessionPool.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import WebKit
import os.log

/// Shared warm `WKWebView` sessions for the home Website tile and saved bookmarks.
///
/// Session objects are cheap; the live `WKWebView` each one can hold is not. The cap
/// therefore bounds *web views*, not sessions: opportunistic warming is skipped once the
/// pool is full and nothing can be evicted, while an explicit `adopt` always succeeds.
/// Thread safety: main-actor only.
@MainActor
final class WarmWebSessionPool {

    static let shared = WarmWebSessionPool()

    /// Hard cap on simultaneously live web views, including the unbound Website tile.
    private let maxWebViews = 6
    private var sessions: [UUID: WarmWebSession] = [:]
    /// Least-recently-used order (oldest at front).
    private var lru: [UUID] = []
    private let logger = Logger(subsystem: "com.eclipseapp.ios", category: "WarmWebPool")

    /// Number of sessions currently holding a live web view.
    private var liveWebViewCount: Int {
        sessions.values.reduce(into: 0) { $0 += $1.hasWebView ? 1 : 0 }
    }

    private init() {}

    // MARK: - Public Interface

    /// Current URL for an existing warm session, if any.
    func currentURL(for pageId: UUID) -> URL? {
        sessions[pageId]?.currentURL
    }

    /// Whether a session is currently inside a phone browser.
    func isAdopted(pageId: UUID) -> Bool {
        sessions[pageId]?.isAdopted == true
    }

    /// Returns (creating if needed) the warm session for `page`.
    ///
    /// Creating a session allocates no web view; that happens on `warm` or `adopt`.
    func session(for page: WebPage) -> WarmWebSession {
        touch(page.id)
        if let existing = sessions[page.id] { return existing }
        let created = WarmWebSession(pageId: page.id)
        sessions[page.id] = created
        return created
    }

    /// Starts loading `page` in a warm web view when idle.
    ///
    /// Opportunistic: skipped when the pool is already at its web-view cap and every
    /// live session is pinned (adopted by a browser, live on AirPlay, or free-browse).
    func warmIfNeeded(for page: WebPage) {
        let session = session(for: page)
        if session.hasWebView {
            session.warm(url: page.url)
            return
        }
        guard makeRoomForNewWebView(retaining: page.id) else {
            logger.notice(
                "Warm pool at capacity; skipping warm for \(page.id.uuidString, privacy: .public)"
            )
            return
        }
        session.warm(url: page.url)
    }

    /// Warms the unbound Website tile (Google) plus every saved bookmark.
    func warmAll() {
        warmIfNeeded(for: WebPage.freeBrowse)
        for page in WebPageStore.shared.pages {
            warmIfNeeded(for: page)
        }
    }

    /// Hands a warm web view to the phone browser for `page`.
    ///
    /// The user asked for this page, so it always succeeds — room is made first, and the
    /// cap may be exceeded by one if every other live session is pinned.
    func adopt(page: WebPage, into remote: WebRemoteViewController) -> WKWebView {
        let session = session(for: page)
        if !session.hasWebView {
            _ = makeRoomForNewWebView(retaining: page.id)
        }
        return session.adopt(into: remote, url: page.url)
    }

    /// Parks a session after the phone browser closes.
    func relinquish(pageId: UUID, from remote: WebRemoteViewController) {
        sessions[pageId]?.relinquish(from: remote)
    }

    /// Attaches a parked warm web view into the home LiveHeader preview host.
    @discardableResult
    func attachPreview(pageId: UUID, to host: UIView) -> Bool {
        guard let session = sessions[pageId], !session.isAdopted else { return false }
        touch(pageId)
        return session.attachPreview(to: host)
    }

    /// Parks a preview that was showing in the LiveHeader.
    func parkPreview(pageId: UUID) {
        sessions[pageId]?.parkOffscreen()
    }

    /// Drops a session when a bookmark is deleted.
    func remove(pageId: UUID) {
        guard pageId != WebPage.freeBrowseId else { return }
        sessions[pageId]?.destroy()
        sessions[pageId] = nil
        lru.removeAll { $0 == pageId }
    }

    // MARK: - Private Helpers

    private func touch(_ pageId: UUID) {
        lru.removeAll { $0 == pageId }
        lru.append(pageId)
    }

    /// Evicts least-recently-used web views until one more can be created.
    /// - Returns: Whether there is now room under `maxWebViews`.
    private func makeRoomForNewWebView(retaining pageId: UUID) -> Bool {
        while liveWebViewCount >= maxWebViews {
            guard let victim = evictionCandidate(retaining: pageId) else { return false }
            logger.debug("Evicting warm web view \(victim.uuidString, privacy: .public)")
            sessions[victim]?.destroy()
            sessions[victim] = nil
            lru.removeAll { $0 == victim }
        }
        return true
    }

    /// Oldest session holding a web view that is not pinned by the UI.
    private func evictionCandidate(retaining pageId: UUID) -> UUID? {
        lru.first { id in
            id != pageId
                && id != WebPage.freeBrowseId
                && id != ExternalDisplayManager.shared.liveWebPageId
                && sessions[id]?.hasWebView == true
                && sessions[id]?.isAdopted != true
        }
    }
}
