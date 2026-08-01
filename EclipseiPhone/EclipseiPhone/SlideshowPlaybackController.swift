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
    /// Set when the user ribbon-taps or swipes; enables Resume after leaving mid-show.
    private var userDidNavigateManually = false
    /// Last interrupted position after a manual advance (cleared on Restart / natural end).
    private var interruptedResume: InterruptedResume?

    private struct InterruptedResume {
        let slideshowId: UUID
        let slideId: String
        let index: Int
    }

    private init() {}

    /// Starts presenting `slideshow` from `startingAt` (clamped to available images).
    func play(
        _ slideshow: Slideshow,
        connectionManager: iPhoneConnectionManager,
        startingAt: Int = 0
    ) {
        let wasActive = activeSlideshowId != nil
        // Leaving a prior run (e.g. switching shows) still updates that tile cover.
        if wasActive { promoteCurrentSlideToCover() }
        // Don't treat "start / restart" as an interrupt worth remembering.
        resetPlaybackState()
        clearResume(for: slideshow.id)
        if wasActive { notifyChanged() }

        let ids = Self.playableSlideIds(in: slideshow)
        guard !ids.isEmpty else { return }

        self.connectionManager = connectionManager
        activeSlideshowId = slideshow.id
        activeSlideIds = ids
        currentSlideIndex = min(max(0, startingAt), ids.count - 1)
        autoplay = slideshow.autoplay
        loop = slideshow.loop
        userDidNavigateManually = false

        applyTransitionOverride(crossfade: slideshow.crossfade)
        presentCurrent()
        rescheduleAutoplayIfNeeded()
        notifyChanged()
    }

    /// Stops the timer and clears active state (keeps last frame on screen).
    ///
    /// If the user had manually advanced, remembers that slide for Resume.
    /// The slideshow tile cover updates to the last slide that was on screen.
    func stop() {
        let hadActive = activeSlideshowId != nil
        promoteCurrentSlideToCover()
        rememberResumeIfInterrupted()
        resetPlaybackState()
        if hadActive { notifyChanged() }
    }

    /// True when `id` is the slideshow currently driving live output.
    func isLive(slideshowId id: UUID) -> Bool {
        activeSlideshowId == id
    }

    /// Resume index after a manual mid-show leave, if the slide is still present.
    func resumeIndex(for slideshow: Slideshow) -> Int? {
        guard let resume = interruptedResume,
              resume.slideshowId == slideshow.id else { return nil }
        let ids = Self.playableSlideIds(in: slideshow)
        if let idx = ids.firstIndex(of: resume.slideId) { return idx }
        guard ids.indices.contains(resume.index) else {
            clearResume(for: slideshow.id)
            return nil
        }
        return resume.index
    }

    /// Drops a saved Resume point (Restart, delete, or natural finish).
    func clearResume(for slideshowId: UUID) {
        guard interruptedResume?.slideshowId == slideshowId else { return }
        interruptedResume = nil
    }

    /// Jumps to `index` (ribbon tap). Reschedules Autoplay when enabled.
    func goToSlide(at index: Int) {
        guard activeSlideshowId != nil,
              activeSlideIds.indices.contains(index),
              index != currentSlideIndex else { return }
        userDidNavigateManually = true
        currentSlideIndex = index
        presentCurrent()
        rescheduleAutoplayIfNeeded()
        notifyChanged()
    }

    /// Steps by `delta` (hero swipe / remote). Wraps when Loop is on; otherwise stops at ends.
    func goToAdjacentSlide(delta: Int) {
        guard activeSlideshowId != nil, !activeSlideIds.isEmpty, delta != 0 else { return }
        let count = activeSlideIds.count
        var next = currentSlideIndex + delta
        if loop {
            next = ((next % count) + count) % count
        } else {
            guard activeSlideIds.indices.contains(next) else { return }
        }
        goToSlide(at: next)
    }

    // MARK: - Private

    private static func playableSlideIds(in slideshow: Slideshow) -> [String] {
        slideshow.itemIds.filter { id in
            guard let item = TVLibraryStore.shared.items.first(where: { $0.id == id }) else {
                return false
            }
            return !item.isVideo && item.isAvailable != false
        }
    }

    private func rememberResumeIfInterrupted() {
        guard userDidNavigateManually,
              let id = activeSlideshowId,
              activeSlideIds.indices.contains(currentSlideIndex),
              currentSlideIndex > 0
        else { return }
        interruptedResume = InterruptedResume(
            slideshowId: id,
            slideId: activeSlideIds[currentSlideIndex],
            index: currentSlideIndex
        )
    }

    /// Tile art follows the last slide that was live when the run ends.
    private func promoteCurrentSlideToCover() {
        guard let id = activeSlideshowId,
              activeSlideIds.indices.contains(currentSlideIndex)
        else { return }
        SlideshowStore.shared.setCover(
            itemId: activeSlideIds[currentSlideIndex],
            slideshowId: id
        )
    }

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
        if let id = activeSlideshowId {
            clearResume(for: id)
        }
        promoteCurrentSlideToCover()
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
        userDidNavigateManually = false
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
