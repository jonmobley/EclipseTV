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

    /// Tile tap: opens the room and goes live, or re-syncs a card already live.
    ///
    /// One tap, like every other card in a Show — see `LivePollTap`. Blackout,
    /// Background, and Screensaver selection is dropped by whichever branch
    /// takes program, so a refused tap leaves the live item alone.
    func selectLivePoll(_ item: ShowLivePoll) {
        let poll = QuestPollSessionStore.shared
        switch LivePollTap.action(
            ownsRoom: poll.membershipId == item.id && poll.session != nil,
            roomIsOnProgram: ExternalDisplayManager.shared.isQuestPollLive
        ) {
        case .refreshProjector:
            refreshLivePollPresentation()
            scrollLiveSlideshowRibbonToCurrentSlide()
            startQuestPollStatusPolling()
        case .presentRoom:
            presentQuestPollLive()
        case .start:
            startLivePoll(item)
        }
    }

    /// ⋯ menu Practice: phone-hero deck preview without creating a room.
    func practiceLivePoll(_ item: ShowLivePoll) {
        guard !blockLiveChangeIfLocked() else { return }
        // A photo or Show tool is cleared below, but an overlay with no display
        // to sit on cannot be: the phone hero is its only output, so taking it
        // for a rehearsal retired it while its tile still read live.
        guard !livePollPracticeBlockedByPhoneHeroOverlay else {
            onStatusMessage?("Stop what's live on this iPhone to practice this poll.")
            return
        }
        // The rehearsal preview replaces the QuestPoll stage, and the room it
        // belongs to stays open — so an audience would lose the stage with the
        // room still running. End the room instead; the ⋯ menu offers that.
        guard !ExternalDisplayManager.shared.isQuestPollLive else {
            onStatusMessage?("End the live poll before practicing a deck.")
            return
        }
        isBlackSelected = false
        isLogoSelected = false
        isScreensaverSelected = false
        SlideshowPlaybackController.shared.stop()
        store.updateCurrentId(nil)
        stopQuestPollStatusPolling()
        QuestPollSessionStore.shared.setPracticeMembershipId(item.id)
        let page = QuestPollConfig.previewPage(pollId: item.pollId)
        WarmWebSessionPool.shared.warmIfNeeded(for: page)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        refreshLivePollPresentation()
    }

    /// Leaves Practice, returning the hero to whatever is on program.
    func stopPracticingLivePoll() {
        QuestPollSessionStore.shared.setPracticeMembershipId(nil)
        refreshLivePollPresentation()
    }

    /// Creates/replaces the global room and goes live for this card.
    ///
    /// Lock and destination are checked before the room exists: refusing after
    /// `startSession` leaves a room open with nothing on the projector.
    func startLivePoll(_ item: ShowLivePoll) {
        guard !blockLiveChangeIfLocked(), ensureQuestPollDestination() else {
            return
        }
        confirmStartOrReplaceQuestPoll(item)
    }

    /// Puts the projector page in the Show hero (and on AirPlay / Practice Mode).
    func presentQuestPollLive() {
        guard QuestPollSessionStore.shared.session != nil else { return }
        guard ensureQuestPollDestination() else { return }
        guard !blockLiveChangeIfLocked() else { return }
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
        let code = QuestPollSessionStore.shared.session?.code
        let page = QuestPollConfig.previewPage(code: code)
        let title = QuestPollSessionStore.shared.session?.deckTitle ?? "Live Poll"
        let canShow = !WarmWebSessionPool.shared.isAdopted(pageId: page.id)
        if canShow {
            WarmWebSessionPool.shared.warmIfNeeded(for: page)
        }
        // LIVE means an external display owns the output. Phone-only / Practice
        // preview shows the projector page without the red chip.
        liveHeader.configureOverlay(
            title: title,
            systemImage: "chart.bar.fill",
            fillColor: UIColor(white: 0.12, alpha: 1),
            keepWebPreview: canShow,
            showsLiveBadge: LiveOutputRouting.showsLivePollLiveBadge()
        )
        if canShow {
            liveHeader.showWebPreview(pageId: page.id)
        }
        liveHeader.allowsHostControllerTap = true
        liveHeader.updatePlayback(PlaybackState())
    }

    /// Join / Question / Results strip while this Show's poll is on program or
    /// in Practice. A leftover room after switching to a photo does not keep
    /// the ribbon (or its red live stroke).
    var showsLivePollRibbon: Bool {
        QuestPollRibbon.shouldShow(
            isShowMode: isShowMode,
            liveRoomActive: openShowId.map { isLivePollLive(inShow: $0) } ?? false,
            isPracticing: canShowLivePollPracticeChrome
                && livePollBelongsToOpenShow(
                    QuestPollSessionStore.shared.practiceMembershipId
                )
        )
    }

    /// True when `membershipId` is a Live Poll card in the open Show.
    func livePollBelongsToOpenShow(_ membershipId: UUID?) -> Bool {
        guard let membershipId, let showId = openShowId else { return false }
        return LivePollStore.shared.poll(id: membershipId)?.showId == showId
    }

    /// Join + Question/Results count for the live ribbon.
    func livePollRibbonItemCount() -> Int {
        guard showsLivePollRibbon else { return 0 }
        return livePollRibbonItems.count
    }

    /// Cues for the live room, or the card's deck while practicing.
    var livePollRibbonItems: [QuestPollRibbonItem] {
        livePollRibbonPresentation.items
    }

    /// Highlighted cue; Join while practicing or in the room's lobby.
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
            isLive: livePollRibbonCueIsLive(at: indexPath.item),
            outlined: true
        )
    }

    /// Cues the tapped Join / Question / Results stage.
    func handleLivePollRibbonTap(at indexPath: IndexPath) {
        guard QuestPollSessionStore.shared.session != nil else { return }
        cueQuestPollStage(at: indexPath.item)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Red stroke on the current cue only while this poll is on program or Practice.
    func livePollRibbonCueIsLive(at index: Int) -> Bool {
        QuestPollRibbon.cueIsLive(
            index: index,
            currentIndex: livePollRibbonIndex,
            pollIsOnProgram: openShowId.map { isLivePollLive(inShow: $0) } ?? false,
            isPracticing: livePollBelongsToOpenShow(
                QuestPollSessionStore.shared.practiceMembershipId
            )
        )
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

    /// Card ⋯ menu: Practice, Replace Poll, Edit, End, Remove.
    ///
    /// Practice is here because the tile tap goes live. It is offered only
    /// while no room is open: a rehearsal replaces the QuestPoll stage without
    /// closing the room behind it, so the choice with a room up is End Poll.
    func livePollContextMenu(_ item: ShowLivePoll) -> UIMenu {
        let poll = QuestPollSessionStore.shared
        let ownsRoom = poll.membershipId == item.id && poll.session != nil
        var children: [UIMenuElement] = []
        if let practice = livePollPracticeAction(item) {
            children.append(practice)
        }
        children.append(contentsOf: [
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
        ])
        if ownsRoom {
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

    /// Practice / Stop Practice for the ⋯ menu, or nil while a room is open.
    private func livePollPracticeAction(_ item: ShowLivePoll) -> UIAction? {
        let poll = QuestPollSessionStore.shared
        if poll.practiceMembershipId == item.id {
            return UIAction(
                title: "Stop Practice",
                image: UIImage(systemName: "eye.slash")
            ) { [weak self] _ in
                self?.stopPracticingLivePoll()
            }
        }
        guard poll.session == nil else { return nil }
        return UIAction(
            title: "Practice",
            image: UIImage(systemName: "eye")
        ) { [weak self] _ in
            self?.practiceLivePoll(item)
        }
    }

    /// Ends the room when removing the membership that owns it.
    func endQuestPollIfRemovingMembership(_ membershipId: UUID) {
        guard QuestPollSessionStore.shared.membershipId == membershipId
                || QuestPollSessionStore.shared.practiceMembershipId == membershipId
        else { return }
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

    /// Deck driving the ribbon: the live room, or the card in Practice.
    private var livePollRibbonCard: ShowLivePoll? {
        let store = QuestPollSessionStore.shared
        if let id = store.membershipId, store.session != nil {
            return LivePollStore.shared.poll(id: id)
        }
        if let id = store.practiceMembershipId {
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

    /// Opens native CONTROLS for the live room (Responses / Next / Show QR / End).
    ///
    /// Presented as a half-height undimmed sheet, so the live preview and cue
    /// ribbon above it stay visible and tappable — see `makeNavigation`.
    func presentQuestPollHostController() {
        guard QuestPollSessionStore.shared.session != nil else { return }
        if presentedViewController is UINavigationController,
           (presentedViewController as? UINavigationController)?
            .viewControllers.first is QuestPollHostViewController {
            return
        }
        let nav = QuestPollHostViewController.makeNavigation(
            onAdvance: { [weak self] command in
                self?.sendQuestPollCommands([command])
            },
            onEnd: { [weak self] in
                self?.confirmEndQuestPoll()
            }
        )
        present(nav, animated: true)
    }

    /// Applies a QuestPoll store update without reloading the ribbon on poll ticks.
    ///
    /// Identical 2s status polls post nothing. Vote-count ticks patch the card
    /// caption in place so ⋯ menus stay up. Cue or room changes refresh thumbs.
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
            if QuestPollSessionStore.shared.session != nil {
                startQuestPollStatusPolling()
            } else {
                stopQuestPollStatusPolling()
            }
        }
    }

    /// Patches visible Live Poll captions without recycling cells (keeps ⋯ menus).
    func reloadLivePollTilesInPlace() {
        guard isShowMode, let section = sectionIndex(for: .shows) else { return }
        let store = QuestPollSessionStore.shared
        let membershipId = store.membershipId
        for (index, item) in openShowGridItems.enumerated() {
            guard case .livePoll(let poll) = item else { continue }
            if let membershipId, poll.id != membershipId { continue }
            let path = IndexPath(item: index, section: section)
            guard let cell = collectionView.cellForItem(at: path)
                    as? LibraryThumbnailCell else { continue }
            let subtitle = store.membershipId == poll.id ? store.tileSubtitle : nil
            cell.applySpecialTitle(
                poll.tileTitle(subtitle: subtitle),
                isLive: isShowGridItemLive(item),
                isLocked: isLiveOutputLocked,
                typeIcon: .livePoll
            )
        }
    }

    // MARK: - Display Mode

    /// Reloads `/present` so Landscape ↔ Vertical picks up a new `aspect=`.
    ///
    /// Warm-pool `needsLoad` compares `absoluteString`, so the hero stays on the
    /// old stage unless we rebuild `previewPage` and load. AirPlay uses `presentWeb`.
    func reloadLivePollForDisplayMode() {
        let live = ExternalDisplayManager.shared.isQuestPollLive
        let practicing = QuestPollSessionStore.shared.practiceMembershipId != nil
        guard live || practicing else { return }
        if live {
            let page = QuestPollConfig.previewPage(
                code: QuestPollSessionStore.shared.session?.code
            )
            ExternalDisplayManager.shared.presentWeb(page.url, pageId: page.id)
        }
        refreshLiveHeader()
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
            // Name the Settings switch, not "the phone preview" — the user has to
            // find "Practice Mode" to act on this.
            message = "Live Poll needs AirPlay, HDMI, or Practice Mode."
        }
        let alert = UIAlertController(
            title: "Live Poll", message: message, preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
        return false
    }
}
