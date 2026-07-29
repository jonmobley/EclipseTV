//
//  SlideshowPlaybackController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import UIKit

/// Drives phone → AirPlay / Multipeer slideshow playback (images only).
@MainActor
final class SlideshowPlaybackController {

    static let shared = SlideshowPlaybackController()

    /// Posted when the active slideshow starts, stops, or changes slide.
    static let didChangeNotification = Notification.Name(
        "SlideshowPlaybackController.didChange"
    )

    /// Currently playing slideshow id, if any.
    private(set) var activeSlideshowId: UUID?

    /// Ordered image ids for the active run.
    private(set) var activeSlideIds: [String] = []

    /// Index of the slide currently on AirPlay / TV.
    private(set) var currentSlideIndex: Int = 0

    private weak var connectionManager: iPhoneConnectionManager?
    private var autoplay = false
    private var loop = false
    private var timer: Timer?
    private var savedTransition: ContentTransitionStyle?
    private var didOverrideTransition = false

    private init() {}

    /// Starts presenting `slideshow` from the first available image.
    func play(
        _ slideshow: Slideshow,
        connectionManager: iPhoneConnectionManager
    ) {
        stop()
        let ids = slideshow.itemIds.filter { id in
            guard let item = TVLibraryStore.shared.items.first(where: { $0.id == id }) else {
                return false
            }
            return !item.isVideo && item.isAvailable != false
        }
        guard !ids.isEmpty else { return }

        self.connectionManager = connectionManager
        activeSlideshowId = slideshow.id
        activeSlideIds = ids
        currentSlideIndex = 0
        autoplay = slideshow.autoplay
        loop = slideshow.loop

        applyTransitionOverride(crossfade: slideshow.crossfade)
        presentCurrent()
        rescheduleAutoplayIfNeeded()
        notifyChanged()
    }

    /// Stops the timer and clears active state (keeps last frame on screen).
    func stop() {
        let hadActive = activeSlideshowId != nil
        resetPlaybackState()
        if hadActive { notifyChanged() }
    }

    /// True when `id` is the slideshow currently driving live output.
    func isLive(slideshowId id: UUID) -> Bool {
        activeSlideshowId == id
    }

    /// Jumps to `index` (ribbon tap). Reschedules Autoplay when enabled.
    func goToSlide(at index: Int) {
        guard activeSlideshowId != nil,
              activeSlideIds.indices.contains(index),
              index != currentSlideIndex else { return }
        currentSlideIndex = index
        presentCurrent()
        rescheduleAutoplayIfNeeded()
        notifyChanged()
    }

    // MARK: - Private

    /// Presents the current slide, dropping any whose media has since gone away.
    ///
    /// A slide deleted mid-run used to blank the display and leave the show apparently
    /// stalled on it, because the old version simply returned without advancing.
    private func presentCurrent() {
        while !activeSlideIds.isEmpty {
            guard activeSlideIds.indices.contains(currentSlideIndex) else {
                currentSlideIndex = 0
                continue
            }
            if presentSlide(at: currentSlideIndex) { return }
            activeSlideIds.remove(at: currentSlideIndex)
            if currentSlideIndex >= activeSlideIds.count { currentSlideIndex = 0 }
        }
        finishPlayback()
    }

    /// - Returns: Whether the slide could actually be shown.
    private func presentSlide(at index: Int) -> Bool {
        let store = TVLibraryStore.shared
        guard let item = store.items.first(where: { $0.id == activeSlideIds[index] }) else {
            return false
        }

        if let connectionManager, connectionManager.sendPlayRequest(id: item.id) {
            store.updateCurrentId(item.id)
            ExternalDisplayManager.shared.present(
                .forLibraryItem(item, thumbnail: store.thumbnail(for: item.id))
            )
            return true
        }
        if let url = LocalMediaStore.shared.localURL(forId: item.id) {
            store.updateCurrentId(item.id)
            ExternalDisplayManager.shared.present(
                .image(url, fill: MediaFitSettings.isFill(forId: item.id))
            )
            return true
        }
        return false
    }

    private func rescheduleAutoplayIfNeeded() {
        timer?.invalidate()
        timer = nil
        guard autoplay, let id = activeSlideshowId,
              let show = SlideshowStore.shared.slideshow(id: id) else { return }
        scheduleAdvance(after: TimeInterval(show.autoplaySeconds.rawValue))
    }

    private func scheduleAdvance(after seconds: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.advance()
            }
        }
    }

    private func advance() {
        guard activeSlideshowId != nil, !activeSlideIds.isEmpty else { return }
        if currentSlideIndex + 1 < activeSlideIds.count {
            currentSlideIndex += 1
            presentCurrent()
            rescheduleAutoplayIfNeeded()
            notifyChanged()
            return
        }
        if loop {
            currentSlideIndex = 0
            presentCurrent()
            rescheduleAutoplayIfNeeded()
            notifyChanged()
            return
        }
        finishPlayback()
    }

    /// Ends a run, keeping the last frame on screen. Shares `stop()`'s reset so a stale
    /// `connectionManager`, `autoplay`, or `loop` can't leak into the next slideshow —
    /// the previous inline version cleared only some of those fields.
    private func finishPlayback() {
        resetPlaybackState()
        notifyChanged()
    }

    private func resetPlaybackState() {
        timer?.invalidate()
        timer = nil
        activeSlideshowId = nil
        activeSlideIds = []
        currentSlideIndex = 0
        autoplay = false
        loop = false
        let manager = connectionManager
        connectionManager = nil
        restoreTransitionOverride(using: manager)
    }

    private func notifyChanged() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    private func applyTransitionOverride(crossfade: Bool) {
        savedTransition = ExternalOutputSettings.contentTransition
        didOverrideTransition = true
        let style: ContentTransitionStyle = crossfade ? .crossfade : .cut
        guard ExternalOutputSettings.contentTransition != style else { return }
        ExternalOutputSettings.contentTransition = style
        connectionManager?.sendSetContentTransition(style.rawValue)
    }

    private func restoreTransitionOverride(using manager: iPhoneConnectionManager?) {
        guard didOverrideTransition, let savedTransition else {
            didOverrideTransition = false
            self.savedTransition = nil
            return
        }
        didOverrideTransition = false
        self.savedTransition = nil
        guard ExternalOutputSettings.contentTransition != savedTransition else { return }
        ExternalOutputSettings.contentTransition = savedTransition
        manager?.sendSetContentTransition(savedTransition.rawValue)
    }
}
