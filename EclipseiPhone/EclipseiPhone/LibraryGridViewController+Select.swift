//
//  LibraryGridViewController+Select.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Select (Show mode multi-select)

extension LibraryGridViewController {

    /// Enters multi-select for the open Show's surface tiles.
    /// - Parameter seedId: Membership / tool id to pre-select (from the ⋯ that opened Select).
    func beginSelecting(seedId: String?) {
        guard isShowMode, !isSelecting else { return }
        if isArranging {
            cancelArranging()
        }
        isSelecting = true
        selectedShowItemIds = []
        if let seedId, isShowSelectionIdSelectable(seedId) {
            selectedShowItemIds.insert(seedId)
        }
        reloadForSelectChange()
        notifySelectChrome()
        Haptics.impactRigid()
        showPresentationToast("Select items, then use Actions")
    }

    /// Leaves select mode without applying a bulk action.
    func cancelSelecting() {
        guard isSelecting else { return }
        endSelectMode()
    }

    /// Checkmark / empty-circle chrome for a Show tile while selecting.
    func applySelectAppearance(to cell: LibraryThumbnailCell, at indexPath: IndexPath) {
        guard isSelecting, isShowMode,
              homeSection(at: indexPath.section) == .shows else {
            return
        }
        let items = openShowGridItems
        guard items.indices.contains(indexPath.item) else { return }
        let item = items[indexPath.item]
        let selectable = isShowGridItemSelectable(item)
        let id = item.selectionId
        let selected = id.map { selectedShowItemIds.contains($0) } ?? false
        cell.setShowSelectMode(
            enabled: true,
            isSelected: selected,
            isSelectable: selectable
        )
        // Live surface tiles can't be checked — dim them like arrange pins.
        cell.alpha = (id != nil && !selectable) ? 0.45 : 1
    }

    /// Toggles selection for a Show-grid tap while in select mode.
    /// - Returns: `true` when the tap was consumed (caller should skip go-live).
    @discardableResult
    func handleSelectModeTap(at indexPath: IndexPath) -> Bool {
        guard isSelecting else { return false }
        let items = openShowGridItems
        guard items.indices.contains(indexPath.item) else { return true }
        let item = items[indexPath.item]
        guard isShowGridItemSelectable(item),
              let id = item.selectionId else { return true }
        if selectedShowItemIds.contains(id) {
            selectedShowItemIds.remove(id)
        } else {
            selectedShowItemIds.insert(id)
        }
        if let cell = collectionView.cellForItem(at: indexPath) as? LibraryThumbnailCell {
            applySelectAppearance(to: cell, at: indexPath)
        }
        notifySelectChrome()
        Haptics.selection()
        return true
    }

    /// Confirms and removes every selected member / tool from the open Show.
    func confirmBulkRemoveFromShow() {
        guard isSelecting, let showId = openShowId else { return }
        let ids = Array(selectedShowItemIds)
        guard !ids.isEmpty else { return }
        let count = ids.count
        let alert = UIAlertController(
            title: count == 1 ? "Remove Item?" : "Remove \(count) Items?",
            message: "Selected items leave this Show. Media stays in your library.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Remove", style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.endSelectMode()
            for id in ids {
                if ShowToolToken.isTool(id) {
                    LocalAlbumStore.shared.hideTool(id, albumId: showId)
                } else if let countdownId = ShowCountdownToken.countdownId(from: id) {
                    self.endCountdownIfDeleting(countdownId)
                    CountdownStore.shared.delete(id: countdownId)
                } else if let livePollId = ShowLivePollToken.livePollId(from: id) {
                    self.endQuestPollIfRemovingMembership(livePollId)
                    LivePollStore.shared.delete(id: livePollId)
                } else {
                    LocalAlbumStore.shared.remove(itemId: id, fromAlbumId: showId)
                }
            }
            Haptics.success()
        })
        present(alert, animated: true)
    }

    /// Builds the header Actions menu for the current selection count.
    func selectActionsMenu() -> UIMenu? {
        guard isSelecting, !selectedShowItemIds.isEmpty else { return nil }
        let count = selectedShowItemIds.count
        let ids = Array(selectedShowItemIds)
        var children: [UIMenuElement] = [copyToShowMenu(ids: ids)]
        if let slideshow = createSlideshowAction() {
            children.append(slideshow)
        }
        children.append(UIAction(
            title: count == 1 ? "Remove" : "Remove \(count) Items",
            image: UIImage(systemName: "folder.badge.minus"),
            attributes: .destructive
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.confirmBulkRemoveFromShow() }
        })
        return UIMenu(children: children)
    }

    /// Drops ids that are no longer in the Show or became live.
    func pruneShowSelection() {
        guard isSelecting else { return }
        let before = selectedShowItemIds.count
        selectedShowItemIds = Set(
            selectedShowItemIds.filter { isShowSelectionIdSelectable($0) }
        )
        if selectedShowItemIds.count != before {
            notifySelectChrome()
        }
    }

    /// True when this surface id can be checked (present, not live).
    func isShowSelectionIdSelectable(_ id: String) -> Bool {
        guard let item = openShowGridItems.first(where: { $0.selectionId == id })
        else { return false }
        return isShowGridItemSelectable(item)
    }

    /// Surface members / tools that are not currently live.
    func isShowGridItemSelectable(_ item: ShowGridItem) -> Bool {
        guard item.selectionId != nil else { return false }
        return !isShowGridItemLive(item)
    }

    /// Live stroke for Show tiles: the director snapshot for operators, otherwise the
    /// same `currentLiveProgram()` that snapshot is built from.
    func isShowGridItemLive(_ item: ShowGridItem) -> Bool {
        if ShowLiveSession.shared.isRemoteOperator {
            return isShowGridItemLiveRemotely(item)
        }
        // Practice lights the poll card without anything on program output.
        if case .livePoll(let poll) = item,
           QuestPollSessionStore.shared.practiceMembershipId == poll.id {
            return true
        }
        guard let program = currentLiveProgram(), !program.isBlackout else {
            return false
        }
        return item.matches(program)
    }

    // MARK: - Private

    /// Nested Show list so destinations appear inside Actions, not a second sheet.
    private func copyToShowMenu(ids: [String]) -> UIMenuElement {
        let groups = copyToShowDestinationGroups()
        guard !groups.isEmpty else {
            return UIAction(
                title: "Copy to Show",
                subtitle: "No other Shows",
                image: UIImage(systemName: "folder.badge.plus"),
                attributes: .disabled
            ) { _ in }
        }
        return UIMenu(
            title: "Copy to Show",
            image: UIImage(systemName: "folder.badge.plus"),
            children: groups.map { group in
                UIMenu(
                    title: "",
                    options: .displayInline,
                    children: group.map { show in
                        UIAction(
                            title: show.name,
                            image: UIImage(systemName: show.showPickerIconName)
                        ) { [weak self] _ in
                            self?.copySelection(ids, toAlbumId: show.id)
                        }
                    }
                )
            }
        )
    }

    private func copyToShowDestinationGroups() -> [[LocalAlbum]] {
        guard let openId = openShowId else { return [] }
        return ShowCopyDestinations.grouped(
            albums: LocalAlbumStore.shared.albums,
            excluding: openId,
            activeOrientation: ExternalOutputSettings.orientation
        )
    }

    private func copySelection(_ ids: [String], toAlbumId albumId: UUID) {
        endSelectMode()
        for id in ids {
            if ShowToolToken.isTool(id) {
                LocalAlbumStore.shared.showTool(id, albumId: albumId)
            } else if let countdownId = ShowCountdownToken.countdownId(from: id),
                      let source = CountdownStore.shared.countdown(id: countdownId) {
                _ = try? CountdownStore.shared.create(
                    name: source.name,
                    showId: albumId,
                    duration: source.duration,
                    layout: source.layout,
                    background: source.background
                )
            } else if let livePollId = ShowLivePollToken.livePollId(from: id),
                      let source = LivePollStore.shared.poll(id: livePollId) {
                LivePollStore.shared.create(
                    pollId: source.pollId,
                    title: source.title,
                    questionCount: source.questionCount,
                    showId: albumId
                )
            } else {
                LocalAlbumStore.shared.add(itemId: id, toAlbumId: albumId)
            }
        }
        let name = LocalAlbumStore.shared.album(id: albumId)?.name ?? "Show"
        showPresentationToast("Copied to \(name)")
        Haptics.success()
    }

    /// Leaves select mode after a bulk action applies.
    func endSelectMode() {
        isSelecting = false
        selectedShowItemIds = []
        reloadForSelectChange()
        notifySelectChrome()
    }

    /// Cross-fades into/out of select mode with thumbnail pins held warm.
    private func reloadForSelectChange() {
        UIView.transition(
            with: collectionView,
            duration: 0.2,
            options: .transitionCrossDissolve
        ) {
            self.reloadLibraryGrid()
        }
    }

    private func notifySelectChrome() {
        onSelectingChanged?(isSelecting)
    }
}
