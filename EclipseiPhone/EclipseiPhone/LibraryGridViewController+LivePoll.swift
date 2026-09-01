//
//  LibraryGridViewController+LivePoll.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

extension LibraryGridViewController {

    /// True when the phone, AirPlay / HDMI, or Practice can show the projector.
    /// EclipseTV-only still cannot render a WKWebView.
    var canPresentQuestPollOverlay: Bool {
        LiveOutputRouting.canHostLivePoll(
            airPlayConnected: ExternalDisplayManager.shared.isConnected,
            eclipseTVOnline: TVLibraryStore.shared.isOnline,
            practiceMode: prefersDisconnectedLivePreview
        )
    }

    /// True when this Show's Live Poll card is on the projector.
    func isLivePollLive(inShow showId: UUID) -> Bool {
        guard ExternalDisplayManager.shared.isQuestPollLive,
              let membershipId = QuestPollSessionStore.shared.membershipId
        else { return false }
        return LivePollStore.shared.poll(id: membershipId)?.showId == showId
    }

    /// + menu: link if needed, pick a deck, append a named card to the Show.
    func addLivePollCard(toShowId showId: UUID) {
        presentQuestPollPickerOrLink(mode: .add(showId: showId))
    }

    /// Tile tap: live card refreshes projector; otherwise show Practice / Start.
    func selectLivePoll(_ item: ShowLivePoll) {
        isBlackSelected = false
        isLogoSelected = false
        isScreensaverSelected = false
        if QuestPollSessionStore.shared.membershipId == item.id,
           QuestPollSessionStore.shared.session != nil {
            livePollGateMembershipId = nil
            if ExternalDisplayManager.shared.isQuestPollLive {
                refreshLivePollPresentation()
                scrollLiveSlideshowRibbonToCurrentSlide()
                startQuestPollStatusPolling()
            } else {
                presentQuestPollLive()
            }
            return
        }
        if QuestPollSessionStore.shared.practiceMembershipId == item.id {
            livePollGateMembershipId = nil
            practiceLivePoll(item)
            return
        }
        livePollGateMembershipId = item.id
        QuestPollSessionStore.shared.setPracticeMembershipId(nil)
        store.updateCurrentId(nil)
        refreshLivePollPresentation()
    }

    /// Phone-hero deck preview without creating a QuestPoll room.
    func practiceLivePoll(_ item: ShowLivePoll) {
        guard !blockLiveChangeIfLocked() else { return }
        livePollGateMembershipId = nil
        isBlackSelected = false
        isLogoSelected = false
        isScreensaverSelected = false
        SlideshowPlaybackController.shared.stop()
        store.updateCurrentId(nil)
        stopQuestPollStatusPolling()
        if ExternalDisplayManager.shared.isQuestPollLive {
            ExternalDisplayManager.shared.stopWebAndRestoreLibrary()
        }
        QuestPollSessionStore.shared.setPracticeMembershipId(item.id)
        let page = QuestPollConfig.previewPage(pollId: item.pollId)
        WarmWebSessionPool.shared.warmIfNeeded(for: page)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        refreshLivePollPresentation()
    }

    /// Creates/replaces the global room and goes live for this card.
    func startLivePoll(_ item: ShowLivePoll) {
        livePollGateMembershipId = nil
        guard ensureQuestPollDestination() else {
            livePollGateMembershipId = item.id
            refreshLivePollPresentation()
            return
        }
        confirmStartOrReplaceQuestPoll(item)
    }

    /// Puts the projector page in the Show hero (and on AirPlay / Practice Mode).
    func presentQuestPollLive() {
        guard QuestPollSessionStore.shared.session != nil else { return }
        guard ensureQuestPollDestination() else { return }
        guard !blockLiveChangeIfLocked() else { return }
        livePollGateMembershipId = nil
        QuestPollSessionStore.shared.setPracticeMembershipId(nil)
        isBlackSelected = false
        isLogoSelected = false
        isScreensaverSelected = false
        SlideshowPlaybackController.shared.stop()
        store.updateCurrentId(nil)
        let code = QuestPollSessionStore.shared.session?.code
        let page = QuestPollConfig.previewPage(code: code)
        WarmWebSessionPool.shared.warmIfNeeded(for: page)
        ExternalDisplayManager.shared.presentWeb(page.url, pageId: page.id)
        announceAirPlayOverlayIfLinked()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        refreshLivePollPresentation()
        scrollLiveSlideshowRibbonToCurrentSlide()
        startQuestPollStatusPolling()
    }

    /// Shows the live hero when the phone is hosting, then reloads poll chrome.
    func refreshLivePollPresentation() {
        updateHeroVisibility()
        applyHeroChrome()
        reloadLibraryGrid()
        refreshLiveHeader()
        refreshSlideshowRibbonPresentation()
    }

    /// Live hero for the QuestPoll projector (not a generic Website overlay).
    func applyQuestPollLiveHeader() {
        liveHeader.hideLivePollGate()
        let code = QuestPollSessionStore.shared.session?.code
        let page = QuestPollConfig.previewPage(code: code)
        let title = QuestPollSessionStore.shared.session?.pollTitle ?? "Live Poll"
        let canShow = !WarmWebSessionPool.shared.isAdopted(pageId: page.id)
        if canShow {
            WarmWebSessionPool.shared.warmIfNeeded(for: page)
        }
        // LIVE means an external display owns the output. Phone-only / Practice
        // preview shows the projector page without the red chip.
        let onExternal = ExternalDisplayManager.shared.isConnected
        liveHeader.configureOverlay(
            title: title,
            systemImage: "chart.bar.fill",
            fillColor: UIColor(white: 0.12, alpha: 1),
            keepWebPreview: canShow,
            showsLiveBadge: LiveOutputRouting.showsLivePollLiveBadge(
                externalDisplayConnected: onExternal
            )
        )
        if canShow {
            liveHeader.showWebPreview(pageId: page.id)
        }
        liveHeader.allowsHostControllerTap = true
        liveHeader.updatePlayback(PlaybackState())
    }

    /// Practice preview or Practice/Start gate when a card is selected idle.
    func applyLivePollIdleHeaderIfNeeded() -> Bool {
        if ExternalDisplayManager.shared.isQuestPollLive { return false }
        if let membershipId = QuestPollSessionStore.shared.practiceMembershipId,
           let item = LivePollStore.shared.poll(id: membershipId) {
            liveHeader.hideLivePollGate()
            let page = QuestPollConfig.previewPage(pollId: item.pollId)
            let canShow = !WarmWebSessionPool.shared.isAdopted(pageId: page.id)
            if canShow {
                WarmWebSessionPool.shared.warmIfNeeded(for: page)
            }
            liveHeader.configureOverlay(
                title: "\(item.title) · Practice",
                systemImage: "chart.bar.fill",
                fillColor: UIColor(white: 0.12, alpha: 1),
                keepWebPreview: canShow,
                showsLiveBadge: false
            )
            if canShow {
                liveHeader.showWebPreview(pageId: page.id)
            }
            liveHeader.updatePlayback(PlaybackState())
            return true
        }
        if let membershipId = livePollGateMembershipId,
           let item = LivePollStore.shared.poll(id: membershipId) {
            liveHeader.showLivePollGate(
                title: item.title,
                onPractice: { [weak self] in self?.practiceLivePoll(item) },
                onStart: { [weak self] in self?.startLivePoll(item) }
            )
            return true
        }
        liveHeader.hideLivePollGate()
        return false
    }

    /// Join / Question / Results strip: live room, Practice preview, or Start gate.
    var showsLivePollRibbon: Bool {
        QuestPollRibbon.shouldShow(
            isShowMode: isShowMode,
            liveRoomActive: QuestPollSessionStore.shared.session != nil,
            isPracticing: QuestPollSessionStore.shared.practiceMembershipId != nil,
            isGated: livePollGateMembershipId != nil
        )
    }

    /// Join + Question/Results count for the live ribbon.
    func livePollRibbonItemCount() -> Int {
        guard showsLivePollRibbon else { return 0 }
        return livePollRibbonItems.count
    }

    /// Cues for the live room, or the card's deck while gated / practicing.
    var livePollRibbonItems: [QuestPollRibbonItem] {
        livePollRibbonPresentation.items
    }

    /// Highlighted cue; Join while waiting to Start or Practice.
    var livePollRibbonIndex: Int {
        livePollRibbonPresentation.index
    }

    /// Configures a ribbon cell for Join, a question, or that question's results.
    func configureLivePollRibbonCell(
        _ cell: LibraryThumbnailCell,
        at indexPath: IndexPath
    ) {
        let items = livePollRibbonItems
        guard items.indices.contains(indexPath.item) else { return }
        let item = items[indexPath.item]
        cell.configureSpecial(
            title: item.title,
            systemImage: item.systemImage,
            thumbnail: nil,
            fillColor: UIColor(white: 0.16, alpha: 1),
            isLive: indexPath.item == livePollRibbonIndex,
            outlined: true
        )
    }

    /// Cues the tapped Join / Question / Results stage.
    func handleLivePollRibbonTap(at indexPath: IndexPath) {
        guard QuestPollSessionStore.shared.session != nil else { return }
        cueQuestPollStage(at: indexPath.item)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Configures a Show-grid Live Poll card (join code / votes when this card is live).
    func configureLivePollTile(
        _ cell: LibraryThumbnailCell,
        item: ShowLivePoll,
        isLive: Bool
    ) {
        let session = QuestPollSessionStore.shared
        let subtitle = session.membershipId == item.id ? session.tileSubtitle : nil
        cell.configureSpecial(
            title: item.tileTitle(subtitle: subtitle),
            systemImage: "chart.bar.fill",
            thumbnail: nil,
            fillColor: UIColor(white: 0.12, alpha: 1),
            isLive: isLive,
            isLocked: isLiveOutputLocked,
            typeIcon: .livePoll
        )
    }

    /// Card ⋯ menu: Replace Poll, Edit, End, Remove.
    func livePollContextMenu(_ item: ShowLivePoll) -> UIMenu {
        var children: [UIMenuElement] = [
            UIAction(
                title: "Replace Poll…",
                image: UIImage(systemName: "list.bullet")
            ) { [weak self] _ in
                self?.presentQuestPollPickerOrLink(mode: .replace(item.id))
            },
            UIAction(
                title: "Edit on QuestPoll",
                image: UIImage(systemName: "safari")
            ) { [weak self] _ in
                self?.presentQuestPollHostEditor()
            }
        ]
        if QuestPollSessionStore.shared.membershipId == item.id,
           QuestPollSessionStore.shared.session != nil {
            children.append(UIAction(
                title: "End Poll",
                image: UIImage(systemName: "stop.circle"),
                attributes: .destructive
            ) { [weak self] _ in
                self?.confirmEndQuestPoll()
            })
        }
        children.append(arrangeAction())
        children.append(selectAction(seedId: ShowLivePollToken.token(for: item.id)))
        children.append(UIAction(
            title: "Remove",
            image: UIImage(systemName: "folder.badge.minus"),
            attributes: .destructive
        ) { [weak self] _ in
            self?.confirmDeleteLivePoll(item)
        })
        return UIMenu(children: children)
    }

    /// Ends the room when removing the membership that owns it.
    func endQuestPollIfRemovingMembership(_ membershipId: UUID) {
        guard QuestPollSessionStore.shared.membershipId == membershipId
                || QuestPollSessionStore.shared.practiceMembershipId == membershipId
                || livePollGateMembershipId == membershipId
        else { return }
        livePollGateMembershipId = nil
        Task { @MainActor [weak self] in
            await self?.endQuestPollSession(clearAccount: false)
        }
    }

    private func confirmDeleteLivePoll(_ item: ShowLivePoll) {
        let alert = UIAlertController(
            title: "Remove Live Poll?",
            message: "Removes “\(item.title)” from this Show.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Remove", style: .destructive) {
            [weak self] _ in
            self?.endQuestPollIfRemovingMembership(item.id)
            LivePollStore.shared.delete(id: item.id)
        })
        present(alert, animated: true)
    }

    // MARK: - Ribbon source

    /// Deck driving the ribbon: live room, Practice, or the Start / Practice gate.
    private var livePollRibbonCard: ShowLivePoll? {
        let store = QuestPollSessionStore.shared
        if let id = store.membershipId, store.session != nil {
            return LivePollStore.shared.poll(id: id)
        }
        if let id = store.practiceMembershipId {
            return LivePollStore.shared.poll(id: id)
        }
        if let id = livePollGateMembershipId {
            return LivePollStore.shared.poll(id: id)
        }
        return nil
    }

    private var livePollRibbonPresentation:
        (items: [QuestPollRibbonItem], index: Int) {
        let store = QuestPollSessionStore.shared
        if store.session != nil {
            return (store.ribbonItems, store.ribbonIndex)
        }
        let count = livePollRibbonCard?.questionCount ?? 1
        return (QuestPollRibbon.items(questionCount: count), 0)
    }

    // MARK: - Session change UI

    /// Opens native CONTROLS for the live room (Responses / Next / QR / End).
    func presentQuestPollHostController() {
        guard QuestPollSessionStore.shared.session != nil else { return }
        if presentedViewController is UINavigationController,
           (presentedViewController as? UINavigationController)?
            .viewControllers.first is QuestPollHostViewController {
            return
        }
        let host = QuestPollHostViewController()
        host.onAdvance = { [weak self] action in
            self?.sendQuestPollActions([action])
        }
        host.onEnd = { [weak self, weak host] in
            host?.dismiss(animated: true) {
                self?.confirmEndQuestPoll()
            }
        }
        let nav = UINavigationController(rootViewController: host)
        nav.modalPresentationStyle = .formSheet
        present(nav, animated: true)
    }

    /// Applies a QuestPoll store update without reloading the ribbon on poll ticks.
    ///
    /// Identical 2s status polls post nothing. Vote/join-code-only updates refresh
    /// the Live Poll tile. Cue or room changes refresh thumbs / scroll once.
    func handleQuestPollSessionChange() {
        switch QuestPollSessionStore.shared.lastChange {
        case .none:
            return
        case .tile:
            reloadLivePollTilesInPlace()
        case .cue:
            reloadLivePollTilesInPlace()
            reloadLivePollRibbonThumbsForCueChange()
        case .session:
            refreshLivePollPresentation()
            if showsLivePollRibbon {
                startQuestPollStatusPolling()
            } else {
                stopQuestPollStatusPolling()
            }
        }
    }

    /// Reloads visible Live Poll cards without resetting ribbon offset.
    func reloadLivePollTilesInPlace() {
        guard isShowMode, let section = sectionIndex(for: .shows) else { return }
        let membershipId = QuestPollSessionStore.shared.membershipId
        let paths = openShowGridItems.enumerated().compactMap { index, item -> IndexPath? in
            guard case .livePoll(let poll) = item else { return nil }
            if let membershipId, poll.id != membershipId { return nil }
            let path = IndexPath(item: index, section: section)
            return collectionView.indexPathsForVisibleItems.contains(path) ? path : nil
        }
        guard !paths.isEmpty else { return }
        collectionView.reloadItems(at: paths)
    }

    // MARK: - Destination

    /// Returns false and alerts when only EclipseTV (or nothing) is available.
    @discardableResult
    func ensureQuestPollDestination() -> Bool {
        if canPresentQuestPollOverlay { return true }
        let message: String
        if TVLibraryStore.shared.isOnline {
            message = "Live Poll needs AirPlay or HDMI. EclipseTV stays on the library."
        } else {
            message = "Live Poll needs AirPlay, HDMI, or the phone preview."
        }
        let alert = UIAlertController(
            title: "Live Poll", message: message, preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
        return false
    }
}
