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
    /// Gap between staggered warm loads, so warming never competes with a tap or scroll.
    private let warmSpacing: TimeInterval = 1.5
    /// Stop waiting on a warm load that never reports back.
    private let warmTimeout: TimeInterval = 8

    private var sessions: [UUID: WarmWebSession] = [:]
    /// Least-recently-used order (oldest at front).
    private var lru: [UUID] = []
    /// Pages waiting their turn to warm.
    private var warmQueue: [WebPage] = []
    /// Page currently loading in the background, if any.
    private var warmInFlight: UUID?
    private var warmWatchdog: DispatchWorkItem?
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
    /// - Returns: Whether a warm load was attempted.
    @discardableResult
    func warmIfNeeded(for page: WebPage) -> Bool {
        warmQueue.removeAll { $0.id == page.id }
        let session = session(for: page)
        if session.hasWebView {
            session.warm(url: page.url)
            return true
        }
        guard makeRoomForNewWebView(retaining: page.id) else {
            logger.notice(
                "Warm pool at capacity; skipping warm for \(page.id.uuidString, privacy: .public)"
            )
            return false
        }
        session.warm(url: page.url)
        return true
    }

    /// Warms the unbound Website tile (Google) only.
    ///
    /// Launch used to warm every saved bookmark at once. Each warm page is a real web
    /// content process parsing and running JavaScript, so a handful of them competed
    /// with the first frame and left the whole app sluggish. Bookmarks now warm as they
    /// scroll into view, via `warmSoon(_:)`.
    func warmFreeBrowse() {
        warmSoon([WebPage.freeBrowse])
    }

    /// Queues `pages` to warm in the background, one load at a time.
    ///
    /// Pages that already hold a live web view are skipped, so this is safe to call
    /// repeatedly from scroll-driven hooks.
    func warmSoon(_ pages: [WebPage]) {
        for page in pages {
            guard sessions[page.id]?.hasWebView != true,
                  page.id != warmInFlight,
                  !warmQueue.contains(where: { $0.id == page.id })
            else {
                continue
            }
            warmQueue.append(page)
        }
        pumpWarmQueue()
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
        warmQueue.removeAll { $0.id == pageId }
        sessions[pageId]?.destroy()
        sessions[pageId] = nil
        lru.removeAll { $0 == pageId }
    }

    // MARK: - Staggered Warming

    /// Warms the next queued page once the previous one has settled.
    private func pumpWarmQueue() {
        guard warmInFlight == nil, !warmQueue.isEmpty else { return }
        let page = warmQueue.removeFirst()
        warmInFlight = page.id

        session(for: page).onWarmSettled = { [weak self] in
            self?.finishWarm(page.id)
        }
        let watchdog = DispatchWorkItem { [weak self] in
            self?.finishWarm(page.id)
        }
        warmWatchdog = watchdog
        DispatchQueue.main.asyncAfter(deadline: .now() + warmTimeout, execute: watchdog)

        if !warmIfNeeded(for: page) {
            finishWarm(page.id)
        }
    }

    private func finishWarm(_ pageId: UUID) {
        guard warmInFlight == pageId else { return }
        warmWatchdog?.cancel()
        warmWatchdog = nil
        warmInFlight = nil
        sessions[pageId]?.onWarmSettled = nil

        guard !warmQueue.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + warmSpacing) { [weak self] in
            self?.pumpWarmQueue()
        }
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
