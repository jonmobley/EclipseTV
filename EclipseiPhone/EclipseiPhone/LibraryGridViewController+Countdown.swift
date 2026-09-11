//
//  LibraryGridViewController+Countdown.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

extension LibraryGridViewController {

    /// Countdown tile: go live, or pause/resume when this timer is already on output.
    func beginCountdown(_ item: ShowCountdown) {
        guard ensureCountdownDestination() else { return }
        // Operator: same tap semantics as local — pause/resume the clock that is
        // already on the director, otherwise ask the director to go live with it.
        if isRemoteCountdownLive(item.id),
           sendShowLiveCommandIfOperator(.countdownToggleRunning) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return
        }
        if sendShowLiveSelectIfOperator(.countdown, itemId: item.id.uuidString) {
            Haptics.impactLight()
            return
        }
        let clock = CountdownController.shared
        if ExternalDisplayManager.shared.isCountdownLive,
           clock.liveCountdownId == item.id {
            clock.toggleRunning()
            Haptics.impactLight()
            return
        }
        presentCountdownLive(item)
    }

    /// Puts this timer in the Show hero (and on AirPlay / Practice).
    func presentCountdownLive(_ item: ShowCountdown) {
        guard ensureCountdownDestination() else { return }
        guard !blockLiveChangeIfLocked() else { return }
        if sendShowLiveSelectIfOperator(.countdown, itemId: item.id.uuidString) {
            Haptics.impactLight()
            return
        }
        isBlackSelected = false
        isLogoSelected = false
        isScreensaverSelected = false
        SlideshowPlaybackController.shared.stop()
        store.updateCurrentId(nil)
        CountdownController.shared.present(item)
        ExternalDisplayManager.shared.presentCountdown()
        announceAirPlayOverlayIfLinked()
        Haptics.impactLight()
        reloadLibraryGrid()
        refreshLiveHeader()
        // Hides a slideshow strip the clock just replaced; the clock has no ribbon.
        refreshSlideshowRibbonPresentation()
    }

    /// Live hero for the countdown clock.
    func applyCountdownLiveHeader() {
        let clock = CountdownController.shared
        liveHeader.configureCountdownClock(
            text: clock.displayString,
            isExpired: clock.remaining == 0
        )
        liveHeader.updatePlayback(PlaybackState())
    }

    /// Duration the chips should mark selected: the director's when operating.
    var selectedCountdownDuration: Int {
        remoteCountdownState?.duration ?? CountdownController.shared.duration
    }

    /// Configures a Show-grid Countdown tile.
    func configureCountdownTile(
        _ cell: LibraryThumbnailCell,
        item: ShowCountdown,
        isLive: Bool
    ) {
        let seconds = isLive
            ? (remoteCountdownState?.remaining ?? CountdownController.shared.remaining)
            : item.duration
        let isExpired = isLive && seconds == 0
        cell.configureCountdown(
            name: item.name,
            seconds: seconds,
            isLive: isLive,
            isLocked: isLiveOutputLocked,
            isExpired: isExpired,
            endHint: item.endAction.tileHint
        )
    }

    /// Pauses and drops the clock when this countdown is deleted while live.
    func endCountdownIfDeleting(_ id: UUID) {
        guard CountdownController.shared.liveCountdownId == id else { return }
        CountdownController.shared.endLive()
        guard ExternalDisplayManager.shared.isCountdownLive else { return }
        if let source = ScreensaverStore.presentationSource {
            ExternalDisplayManager.shared.present(source)
        } else {
            ExternalDisplayManager.shared.clear()
        }
    }

    /// Refreshes hero + visible tiles without reloading the whole grid.
    func refreshCountdownChrome() {
        // Director clock ticks once a second; operators mirror it from the snapshot.
        broadcastShowLiveSnapshotIfNeeded()
        guard ExternalDisplayManager.shared.isCountdownLive else {
            reloadGridIfSafe()
            refreshLiveHeader()
            return
        }
        // A Live Poll Practice preview owns the hero while the clock keeps
        // running on the projector; a tick must not paint the clock back over it.
        guard !showsLivePollPracticeHeader else {
            updateVisibleCountdownTiles()
            return
        }
        let clock = CountdownController.shared
        if liveHeader.countdownClockLabel.isHidden {
            applyCountdownLiveHeader()
        } else {
            liveHeader.applyCountdownClock(
                text: clock.displayString,
                isExpired: clock.remaining == 0
            )
        }
        updateVisibleCountdownTiles()
    }

    /// ⋯ menu: edit layout, duration, background, rename, arrange, delete.
    func countdownContextMenu(_ item: ShowCountdown) -> UIMenu {
        let token = ShowCountdownToken.token(for: item.id)
        var children: [UIMenuElement] = [
            UIAction(
                title: "Edit",
                image: UIImage(systemName: "slider.horizontal.3")
            ) { [weak self] _ in
                self?.presentCountdownLayoutEditor(item)
            }
        ]
        children.append(contentsOf: countdownToolActions(for: item))
        children.append(countdownBackgroundMenu(for: item))
        children.append(UIAction(
            title: "Rename",
            image: UIImage(systemName: "pencil")
        ) { [weak self] _ in
            self?.promptRenameCountdown(item)
        })
        children.append(arrangeAction())
        children.append(selectAction(seedId: token))
        children.append(UIAction(
            title: "Delete Countdown",
            image: UIImage(systemName: "trash"),
            attributes: .destructive
        ) { [weak self] _ in
            self?.confirmDeleteCountdown(item)
        })
        return UIMenu(children: children)
    }

    /// Full-screen drag / pinch canvas for this countdown's output layout.
    func presentCountdownLayoutEditor(_ item: ShowCountdown) {
        let editor = CountdownLayoutEditorViewController(item: item)
        let nav = UINavigationController(rootViewController: editor)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }

    /// Reset and duration chips for a countdown ⋯ menu.
    func countdownToolActions(for item: ShowCountdown) -> [UIMenuElement] {
        // Live here or on the director; both read the same predicate as the tile.
        let isLive = isShowGridItemLive(.countdown(item))
        let selectedDuration = isLive ? selectedCountdownDuration : item.duration
        let reset = UIAction(
            title: "Reset",
            image: UIImage(systemName: "arrow.counterclockwise")
        ) { [weak self] _ in
            guard isLive else { return }
            if self?.sendShowLiveCommandIfOperator(.countdownReset) == true { return }
            CountdownController.shared.reset()
        }
        var durationActions: [UIMenuElement] = CountdownController.durationPresets.map {
            seconds in
            let selected = seconds == selectedDuration
            return UIAction(
                title: CountdownController.displayString(seconds: seconds),
                state: selected ? .on : .off
            ) { [weak self] _ in
                self?.applyCountdownDuration(seconds, to: item.id)
            }
        }
        let isPreset = CountdownController.durationPresets.contains(selectedDuration)
        durationActions.append(UIAction(
            title: "Custom…",
            image: UIImage(systemName: "pencil"),
            state: isPreset ? .off : .on
        ) { [weak self] _ in
            self?.promptCustomCountdownDuration(for: item.id)
        })
        let duration = UIMenu(
            title: "Duration",
            image: UIImage(systemName: "timer"),
            children: durationActions
        )
        return [reset, duration, countdownEndActionMenu(for: item)]
    }

    // MARK: - Destination

    /// Returns false and alerts when only EclipseTV (or nothing) is available.
    @discardableResult
    func ensureCountdownDestination() -> Bool {
        if ShowLiveSession.shared.isRemoteOperator { return true }
        if canPresentQuestPollOverlay { return true }
        let message: String
        if TVLibraryStore.shared.isOnline {
            message = "Countdown needs AirPlay or HDMI. EclipseTV stays on the library."
        } else {
            message = "Countdown needs AirPlay, HDMI, or Practice Mode."
        }
        let alert = UIAlertController(
            title: "Countdown", message: message, preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
        return false
    }

    // MARK: - Private

    /// Ticks the live countdown tile (local clock, or the director's on an operator).
    func updateVisibleCountdownTiles() {
        guard let showsSection = sectionIndex(for: .shows) else { return }
        let remaining = remoteCountdownState?.remaining
            ?? CountdownController.shared.remaining
        for (index, row) in openShowGridItems.enumerated() {
            guard case .countdown(let item) = row,
                  let cell = collectionView.cellForItem(
                    at: IndexPath(item: index, section: showsSection)
                  ) as? LibraryThumbnailCell
            else { continue }
            let isLive = isShowGridItemLive(.countdown(item))
            let seconds = isLive ? remaining : item.duration
            let isExpired = isLive && seconds == 0
            if isLive {
                cell.applyCountdownTime(seconds, isExpired: isExpired)
            }
            var spoken = "\(item.name), \(CountdownController.displayString(seconds: seconds))"
            if let hint = item.endAction.tileHint {
                spoken += ", \(hint.lowercased())"
            }
            cell.accessibilityLabel = isLive
                ? (isLiveOutputLocked
                    ? "\(spoken), live, locked, countdown"
                    : "\(spoken), live, countdown")
                : "\(spoken), countdown"
        }
    }

    func promptCustomCountdownDuration(for itemId: UUID?) {
        CountdownDurationPrompt.present(
            from: self,
            seconds: durationForPrompt(itemId: itemId)
        ) { [weak self] seconds in
            self?.applyCountdownDuration(seconds, to: itemId)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            self?.refreshCountdownChrome()
            self?.refreshSlideshowRibbonPresentation()
        }
    }

    private func durationForPrompt(itemId: UUID?) -> Int {
        if isRemoteCountdownLive(itemId), let remote = remoteCountdownState {
            return remote.duration
        }
        if let itemId,
           CountdownController.shared.liveCountdownId == itemId {
            return CountdownController.shared.duration
        }
        if let itemId, let item = CountdownStore.shared.countdown(id: itemId) {
            return item.duration
        }
        return CountdownController.shared.duration
    }

    private func applyCountdownDuration(_ seconds: Int, to itemId: UUID?) {
        // Operator editing the director's live clock: the director applies it.
        if isRemoteCountdownLive(itemId),
           sendShowLiveCommandIfOperator(
               .countdownSetDuration,
               value: Double(CountdownController.clampedDuration(seconds))
           ) {
            return
        }
        if let itemId, CountdownController.shared.liveCountdownId == itemId,
           ExternalDisplayManager.shared.isCountdownLive {
            CountdownController.shared.setDuration(seconds)
            return
        }
        if let itemId {
            let next = CountdownController.clampedDuration(seconds)
            CountdownStore.shared.setDuration(id: itemId, seconds: next)
            UserDefaults.standard.set(next, forKey: CountdownController.durationKey)
            return
        }
        CountdownController.shared.setDuration(seconds)
    }

    private func promptRenameCountdown(_ item: ShowCountdown) {
        let alert = UIAlertController(
            title: "Rename Countdown", message: nil, preferredStyle: .alert
        )
        alert.addTextField { field in
            field.text = item.name
            field.autocapitalizationType = .words
            UserDisplayName.configureTextField(field)
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { _ in
            let name = alert.textFields?.first?.text ?? ""
            try? CountdownStore.shared.rename(id: item.id, to: name)
        })
        present(alert, animated: true)
    }

    private func confirmDeleteCountdown(_ item: ShowCountdown) {
        let alert = UIAlertController(
            title: "Delete Countdown?",
            message: "“\(item.name)” is removed from this Show.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.endCountdownIfDeleting(item.id)
            CountdownStore.shared.delete(id: item.id)
        })
        present(alert, animated: true)
    }
}
