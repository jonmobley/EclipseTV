//
//  LiveOverlayController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//
//  Description: Which template cards and media overlays are layered on top of
//               the live picture right now, in draw order, plus Blackout and
//               announcement auto-remove. Drives the overlay layer on the
//               external display and on the phone's live preview.
//  Thread Safety: Main actor only.
//

import Combine
import Foundation

// MARK: - RenderedOverlay

/// One overlay ready to draw, resolved from its id.
enum RenderedOverlay: Identifiable, Equatable {
    case card(ShowTemplateCard)
    case media(MediaOverlayEntry)

    var id: LiveOverlayID {
        switch self {
        case .card(let card): return .template(card.id)
        case .media(let entry): return .media(entry.itemId)
        }
    }
}

// MARK: - LiveOverlayController

/// Owns the live overlay stack shared by every output surface.
///
/// Usage: a tile tap calls `toggle(_:)`; the overlay layer views observe this
/// object and redraw `rendered`. Blackout hides every overlay without taking
/// them off, so they come back when Blackout ends.
@MainActor
final class LiveOverlayController: ObservableObject {

    // MARK: - Properties

    static let shared = LiveOverlayController()

    /// Posted when the live set changes (for grid tiles and the hero).
    static let didChangeNotification = Notification.Name("LiveOverlayController.didChange")

    /// Overlays to draw, bottom first; empty while Blackout is on.
    @Published private(set) var rendered: [RenderedOverlay] = []

    private(set) var stack = LiveOverlayStack()
    private var isBlackout = false
    private var autoRemoveWork: [UUID: DispatchWorkItem] = [:]
    private var observers: [NSObjectProtocol] = []
    /// An overlay being dragged or pinched on the hero, drawn in place of the
    /// saved one until the fingers lift.
    private var adjusting: RenderedOverlay?

    // MARK: - Initialization

    private init() {
        observeSources()
    }

    // MARK: - Queries

    /// Whether `id` is on output (even while Blackout hides it).
    func isLive(_ id: LiveOverlayID) -> Bool {
        stack.contains(id)
    }

    /// Whether any overlay is on output.
    var hasLiveOverlays: Bool { !stack.isEmpty }

    // MARK: - Mutations

    /// Puts the overlay on top of what is live, or takes it off when it is on.
    ///
    /// - Returns: Whether the overlay is on output afterwards.
    @discardableResult
    func toggle(_ id: LiveOverlayID) -> Bool {
        let isOn = stack.toggle(id)
        if case .template(let cardId) = id {
            syncAutoRemove(cardId: cardId, isOn: isOn)
        }
        publish()
        return isOn
    }

    /// Takes the overlay off output when it is on.
    func remove(_ id: LiveOverlayID) {
        guard stack.contains(id) else { return }
        stack.remove(id)
        if case .template(let cardId) = id {
            syncAutoRemove(cardId: cardId, isOn: false)
        }
        publish()
    }

    /// Takes every overlay off output.
    func removeAll() {
        guard !stack.isEmpty else { return }
        stack.removeAll()
        autoRemoveWork.values.forEach { $0.cancel() }
        autoRemoveWork.removeAll()
        publish()
    }

    /// Hides (true) or shows again (false) every overlay for Blackout.
    func setBlackout(_ isOn: Bool) {
        guard isBlackout != isOn else { return }
        isBlackout = isOn
        publish()
    }

    /// Draws `overlay` in place of its saved version on every screen while it is
    /// dragged or pinched (nil when the fingers lift). Nothing is saved, and
    /// `didChangeNotification` is not posted, since the live set is unchanged.
    func setAdjusting(_ overlay: RenderedOverlay?) {
        guard adjusting != overlay else { return }
        adjusting = overlay
        publish(notify: false)
    }

    // MARK: - Private

    private func observeSources() {
        let center = NotificationCenter.default
        let names = [
            TemplateCardStore.didChangeNotification,
            MediaOverlayStore.didChangeNotification
        ]
        for name in names {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated { self?.sourcesDidChange() }
            })
        }
        observers.append(center.addObserver(
            forName: ExternalDisplayManager.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.setBlackout(ExternalDisplayManager.shared.isBlackLive)
            }
        })
    }

    /// Drops overlays whose card or media was deleted, then redraws.
    private func sourcesDidChange() {
        stack.prune { resolve($0) != nil }
        publish()
    }

    private func resolve(_ id: LiveOverlayID) -> RenderedOverlay? {
        switch id {
        case .template(let cardId):
            return TemplateCardStore.shared.card(id: cardId).map { .card($0) }
        case .media(let itemId):
            return MediaOverlayStore.shared.entry(for: itemId).map { .media($0) }
        }
    }

    private func stackOrder(of id: LiveOverlayID) -> Int? {
        switch resolve(id) {
        case .card(let card): return card.stackOrder
        case .media(let entry): return entry.stackOrder
        case nil: return nil
        }
    }

    private func publish(notify: Bool = true) {
        var next = isBlackout
            ? []
            : stack.drawOrder(stackOrder: stackOrder(of:)).compactMap(resolve)
        if let adjusting, let index = next.firstIndex(where: { $0.id == adjusting.id }) {
            next[index] = adjusting
        }
        if next != rendered { rendered = next }
        guard notify else { return }
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    /// Announcement cards with "remove after" leave output on their own.
    private func syncAutoRemove(cardId: UUID, isOn: Bool) {
        autoRemoveWork[cardId]?.cancel()
        autoRemoveWork[cardId] = nil
        guard isOn,
              let config = TemplateCardStore.shared.card(id: cardId)?.config,
              config.template == .announcement,
              let seconds = config.autoRemoveAfterSeconds, seconds > 0
        else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.remove(.template(cardId)) }
        }
        autoRemoveWork[cardId] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(seconds), execute: work)
    }
}
