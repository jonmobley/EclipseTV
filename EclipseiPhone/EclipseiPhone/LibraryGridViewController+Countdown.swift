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
        if sendShowLiveSelectIfOperator(.countdown, itemId: item.id.uuidString) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return
        }
        let clock = CountdownController.shared
        if ExternalDisplayManager.shared.isCountdownLive,
           clock.liveCountdownId == item.id {
            clock.toggleRunning()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return
        }
        presentCountdownLive(item)
    }

    /// Puts this timer in the Show hero (and on AirPlay / Practice).
    func presentCountdownLive(_ item: ShowCountdown) {
        guard ensureCountdownDestination() else { return }
        guard !blockLiveChangeIfLocked() else { return }
        if sendShowLiveSelectIfOperator(.countdown, itemId: item.id.uuidString) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        reloadLibraryGrid()
        refreshLiveHeader()
        refreshSlideshowRibbonPresentation()
        scrollLiveSlideshowRibbonToCurrentSlide()
    }

    /// Live hero for the countdown clock.
    func applyCountdownLiveHeader() {
        let clock = CountdownController.shared
        liveHeader.configureOverlay(
            title: clock.displayString,
            systemImage: "timer",
            fillColor: UIColor(white: 0.08, alpha: 1),
            stableContentKey: "overlay:countdown"
        )
        liveHeader.updatePlayback(PlaybackState())
        liveHeader.titleLabel.font = .monospacedDigitSystemFont(
            ofSize: 28, weight: .semibold
        )
    }

    /// Whether the live ribbon is showing duration presets.
    var showsCountdownRibbon: Bool {
        isShowMode && ExternalDisplayManager.shared.isCountdownLive
    }

    /// Duration-preset count plus Custom for the live ribbon.
    func countdownRibbonItemCount() -> Int {
        guard showsCountdownRibbon else { return 0 }
        return CountdownController.durationPresets.count + 1
    }

    /// Configures a ribbon cell for a duration preset or Custom.
    func configureCountdownRibbonCell(
        _ cell: LibraryThumbnailCell,
        at indexPath: IndexPath
    ) {
        let presets = CountdownController.durationPresets
        if indexPath.item == presets.count {
            configureCustomCountdownRibbonCell(cell)
            return
        }
        guard presets.indices.contains(indexPath.item) else { return }
        let seconds = presets[indexPath.item]
        let selected = seconds == CountdownController.shared.duration
        cell.configureSpecial(
            title: CountdownController.displayString(seconds: seconds),
            systemImage: "timer",
            thumbnail: nil,
            fillColor: UIColor(white: 0.16, alpha: 1),
            isLive: selected,
            outlined: !selected,
            typeIcon: .countdown
        )
    }

    /// Configures a Show-grid Countdown tile.
    func configureCountdownTile(
        _ cell: LibraryThumbnailCell,
        item: ShowCountdown,
        isLive: Bool
    ) {
        let remaining = isLive ? CountdownController.shared.remaining : nil
        cell.configureSpecial(
            title: item.tileTitle(remaining: remaining),
            systemImage: "timer",
            thumbnail: nil,
            fillColor: UIColor(white: 0.12, alpha: 1),
            isLive: isLive,
            isLocked: isLiveOutputLocked,
            typeIcon: .countdown
        )
    }

    /// Applies the tapped duration preset, or opens Custom Time.
    func handleCountdownRibbonTap(at indexPath: IndexPath) {
        let presets = CountdownController.durationPresets
        if indexPath.item == presets.count {
            promptCustomCountdownDuration(for: CountdownController.shared.liveCountdownId)
            return
        }
        guard presets.indices.contains(indexPath.item) else { return }
        applyCountdownDuration(presets[indexPath.item], to: clockTargetId())
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        refreshCountdownChrome()
        refreshSlideshowRibbonPresentation()
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
        guard ExternalDisplayManager.shared.isCountdownLive else {
            reloadGridIfSafe()
            refreshLiveHeader()
            return
        }
        applyCountdownLiveHeader()
        updateVisibleCountdownTiles()
    }

    /// ⋯ menu: duration, rename, arrange, delete.
    func countdownContextMenu(_ item: ShowCountdown) -> UIMenu {
        let token = ShowCountdownToken.token(for: item.id)
        var children: [UIMenuElement] = countdownToolActions(for: item)
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

    /// Reset and duration chips for a countdown ⋯ menu.
    func countdownToolActions(for item: ShowCountdown) -> [UIMenuElement] {
        let clock = CountdownController.shared
        let isLive = clock.liveCountdownId == item.id
            && ExternalDisplayManager.shared.isCountdownLive
        let selectedDuration = isLive ? clock.duration : item.duration
        let reset = UIAction(
            title: "Reset",
            image: UIImage(systemName: "arrow.counterclockwise")
        ) { _ in
            guard isLive else { return }
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
                self?.refreshSlideshowRibbonPresentation()
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
        return [reset, duration]
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

    private func configureCustomCountdownRibbonCell(_ cell: LibraryThumbnailCell) {
        let clock = CountdownController.shared
        let selected = !clock.isPresetDuration
        let title = selected
            ? CountdownController.displayString(seconds: clock.duration)
            : "Custom"
        cell.configureSpecial(
            title: title,
            systemImage: "pencil",
            thumbnail: nil,
            fillColor: UIColor(white: 0.16, alpha: 1),
            isLive: selected,
            outlined: !selected,
            typeIcon: .countdown
        )
    }

    private func updateVisibleCountdownTiles() {
        guard let showsSection = sectionIndex(for: .shows) else { return }
        let liveId = CountdownController.shared.liveCountdownId
        for (index, row) in openShowGridItems.enumerated() {
            guard case .countdown(let item) = row,
                  let cell = collectionView.cellForItem(
                    at: IndexPath(item: index, section: showsSection)
                  ) as? LibraryThumbnailCell
            else { continue }
            let isLive = item.id == liveId
                && ExternalDisplayManager.shared.isCountdownLive
            let remaining = isLive ? CountdownController.shared.remaining : nil
            let title = item.tileTitle(remaining: remaining)
            cell.captionLabel.text = title
            cell.accessibilityLabel = isLive
                ? (isLiveOutputLocked ? "\(title), live, locked" : "\(title), live")
                : title
        }
    }

    private func clockTargetId() -> UUID? {
        CountdownController.shared.liveCountdownId
    }

    func promptCustomCountdownDuration(for itemId: UUID?) {
        let seconds = durationForPrompt(itemId: itemId)
        let alert = UIAlertController(
            title: "Custom Time",
            message: "Minutes, m:ss, or h:mm:ss.",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = "7:30"
            field.text = CountdownController.displayString(seconds: seconds)
            field.keyboardType = .numbersAndPunctuation
            field.autocorrectionType = .no
            field.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Set", style: .default) { [weak self] _ in
            self?.applyCustomCountdownDuration(
                alert.textFields?.first?.text, to: itemId
            )
        })
        present(alert, animated: true)
    }

    private func durationForPrompt(itemId: UUID?) -> Int {
        if let itemId,
           CountdownController.shared.liveCountdownId == itemId {
            return CountdownController.shared.duration
        }
        if let itemId, let item = CountdownStore.shared.countdown(id: itemId) {
            return item.duration
        }
        return CountdownController.shared.duration
    }

    private func applyCustomCountdownDuration(_ raw: String?, to itemId: UUID?) {
        guard let seconds = CountdownController.parseDuration(raw ?? "") else {
            presentInvalidCountdownDurationAlert(for: itemId)
            return
        }
        applyCountdownDuration(seconds, to: itemId)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        refreshCountdownChrome()
        refreshSlideshowRibbonPresentation()
    }

    private func applyCountdownDuration(_ seconds: Int, to itemId: UUID?) {
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

    private func presentInvalidCountdownDurationAlert(for itemId: UUID?) {
        let alert = UIAlertController(
            title: "Couldn't Set Time",
            message: "Enter minutes, m:ss, or h:mm:ss — for example 7, 7:30, or 1:15:00.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.promptCustomCountdownDuration(for: itemId)
        })
        present(alert, animated: true)
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
