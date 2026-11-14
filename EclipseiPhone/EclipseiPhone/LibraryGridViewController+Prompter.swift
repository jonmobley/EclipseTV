//
//  LibraryGridViewController+Prompter.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

extension LibraryGridViewController {

    // MARK: - Operator view

    /// Opens one of the open Show's Prompters full screen. Never puts it live by itself.
    ///
    /// There is one Prompter engine, and the output shows whatever script it holds, so
    /// opening a different Prompter while one is on screen asks before switching.
    func presentPrompterOperator(scriptId: UUID) {
        guard !isAlreadyOpen(PrompterViewController.self) else { return }
        let controller = PrompterController.shared
        if ExternalDisplayManager.shared.isPrompterLive,
           let liveScriptId = controller.liveScriptId, liveScriptId != scriptId {
            let alert = UIAlertController(
                title: "Switch Prompter?",
                message: "Another Prompter is on screen. Switch the screen to this script?",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: "Switch", style: .default) { [weak self] _ in
                guard let self else { return }
                // Move the live script and its Show together, so ownership (Home live
                // card, foreign-live mini) follows what the audience now sees.
                if let showId = self.openShowId {
                    PrompterController.shared.prepareLive(showId: showId, scriptId: scriptId)
                    self.reloadLibraryGrid()
                    self.refreshLiveHeader()
                }
                self.openPrompterOperator(scriptId: scriptId)
            })
            topmostPresenter.present(alert, animated: true)
            return
        }
        openPrompterOperator(scriptId: scriptId)
    }

    private func openPrompterOperator(scriptId: UUID) {
        let prompter = PrompterViewController(scriptId: scriptId)
        // A Show Live operator device drives nothing itself: it reads along and
        // edits the script (which syncs), but Go Live stays with the director.
        if !ShowLiveSession.shared.isRemoteOperator {
            prompter.liveActions = .init(
                goLive: { [weak self] in self?.presentPrompterLive(scriptId: scriptId) ?? false },
                stopLive: { [weak self] in self?.stopPrompterLive() }
            )
        }
        // Forwards orientation to the Prompter, which holds the Display Mode shape.
        let nav = DisplayModeNavigationController(rootViewController: prompter)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }

    /// Opens the script editor straight from the tile.
    func presentPrompterScriptEditor(scriptId: UUID) {
        let nav = PrompterScriptEditorViewController.makeNavigation(
            scriptId: scriptId, traits: traitCollection, anchor: nil, arrows: []
        )
        topmostPresenter.present(nav, animated: true)
    }

    // MARK: - Live

    /// Puts one of the open Show's scripts on AirPlay / HDMI (or the Practice hero).
    /// Returns whether it went live.
    @discardableResult
    func presentPrompterLive(scriptId: UUID) -> Bool {
        guard let showId = openShowId else { return false }
        guard ensurePrompterDestination() else { return false }
        guard !blockLiveChangeIfLocked() else { return false }
        isBlackSelected = false
        isLogoSelected = false
        isScreensaverSelected = false
        SlideshowPlaybackController.shared.stop()
        // Bind, then publish the overlay: `liveShowId` and `overlaySource` name the
        // same script before anything observing either of them repaints.
        PrompterController.shared.prepareLive(showId: showId, scriptId: scriptId)
        ExternalDisplayManager.shared.presentPrompter()
        store.updateCurrentId(nil)
        announceAirPlayOverlayIfLinked()
        Haptics.impactLight()
        reloadLibraryGrid()
        refreshLiveHeader()
        refreshSlideshowRibbonPresentation()
        return true
    }

    /// Takes the script off output; the Screensaver (or nothing) takes its place.
    /// The controller keeps its position so the operator can resume.
    func stopPrompterLive() {
        guard ExternalDisplayManager.shared.isPrompterLive else { return }
        ExternalDisplayManager.shared.clear()
        Haptics.impactLight()
        reloadLibraryGrid()
        refreshLiveHeader()
    }

    /// Returns false and alerts when only EclipseTV (or nothing) can show it.
    ///
    /// The prompter is text drawn by this app, so like Countdown it needs AirPlay /
    /// HDMI or Practice Mode; the Apple TV can only play library files.
    @discardableResult
    func ensurePrompterDestination() -> Bool {
        if ShowLiveSession.shared.isRemoteOperator { return false }
        if LiveOutputRouting.canPresentWebOverlay(practiceMode: prefersDisconnectedLivePreview) {
            return true
        }
        let message = TVLibraryStore.shared.isOnline
            ? "Prompter needs AirPlay or HDMI. EclipseTV stays on the library."
            : "Prompter needs AirPlay, HDMI, or Practice Mode."
        let alert = UIAlertController(title: "Prompter", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        topmostPresenter.present(alert, animated: true)
        return false
    }

    /// The controller to present an alert from while the operator view is up.
    private var topmostPresenter: UIViewController {
        var top: UIViewController = self
        while let next = top.presentedViewController, !next.isBeingDismissed {
            top = next
        }
        return top
    }

    // MARK: - Tile

    /// Configures a Show-grid Prompter tile.
    func configurePrompterTile(_ cell: LibraryThumbnailCell, scriptId: UUID, isLive: Bool) {
        let script = PrompterScriptStore.shared.script(forShowId: scriptId)
        cell.configurePrompter(
            excerpt: LibraryThumbnailCell.prompterExcerpt(from: script),
            isLive: isLive,
            isLocked: isLiveOutputLocked,
            isPlaying: isLive && PrompterController.shared.isPlaying
        )
    }

    /// ⋯ menu: open, go live, edit, reset, arrange, select, remove.
    func prompterContextMenu(token: String, scriptId: UUID) -> UIMenu {
        let isLive = isShowGridItemLive(.prompter(token: token, scriptId: scriptId))
        var children: [UIMenuElement] = [
            UIAction(title: "Open", image: UIImage(systemName: "text.alignleft")) { [weak self] _ in
                self?.presentPrompterOperator(scriptId: scriptId)
            }
        ]
        if !ShowLiveSession.shared.isRemoteOperator {
            if isLive {
                children.append(UIAction(title: "Stop Live", image: UIImage(systemName: "stop.fill")) { [weak self] _ in
                    self?.stopPrompterLive()
                })
            } else {
                children.append(UIAction(
                    title: "Go Live",
                    image: UIImage(systemName: "antenna.radiowaves.left.and.right"),
                    attributes: PrompterScriptStore.shared.hasScript(forShowId: scriptId) ? [] : .disabled
                ) { [weak self] _ in
                    self?.presentPrompterLive(scriptId: scriptId)
                })
            }
        }
        children.append(UIAction(title: "Edit Script", image: UIImage(systemName: "pencil")) { [weak self] _ in
            self?.presentPrompterScriptEditor(scriptId: scriptId)
        })
        // The one Prompter engine holds one script's position; reset only that one.
        children.append(UIAction(
            title: "Reset to Top",
            image: UIImage(systemName: "backward.end.fill"),
            attributes: PrompterController.shared.boundScriptId == scriptId ? [] : .disabled
        ) { _ in
            PrompterController.shared.reset()
        })
        children.append(arrangeAction())
        children.append(selectAction(seedId: token))
        if let showId = openShowId {
            children.append(UIAction(
                title: "Remove from Show",
                image: UIImage(systemName: "eye.slash"),
                attributes: .destructive
            ) { [weak self] _ in
                if isLive { self?.stopPrompterLive() }
                self?.removeFromShowWithUndo([token], showId: showId)
            })
        }
        return UIMenu(children: children)
    }

    // MARK: - Hero

    /// Live hero: the lines around the reading guide.
    func applyPrompterLiveHeader() {
        let controller = PrompterController.shared
        let anchor = controller.readingAnchor
        let around = controller.layout.lines(around: anchor)
        liveHeader.configurePrompterLive(
            lines: around.lines,
            currentIndex: around.currentIndex,
            lineIndex: controller.layout.lineIndex(for: anchor),
            isPlaying: controller.isPlaying
        )
        liveHeader.updatePlayback(PlaybackState())
    }

    /// Refreshes hero + the Prompter tile after a controller change (play, speed,
    /// live state), without reloading the grid on every frame.
    func refreshPrompterChrome() {
        guard ExternalDisplayManager.shared.isPrompterLive else {
            reloadGridIfSafe()
            refreshLiveHeader()
            return
        }
        guard !showsLivePollPracticeHeader else { return }
        applyPrompterLiveHeader()
        updateVisiblePrompterTile()
    }

    /// Per-frame: repaint the hero lines only when the reading line changes.
    func updatePrompterHeroIfLineChanged() {
        guard ExternalDisplayManager.shared.isPrompterLive,
              !showsLivePollPracticeHeader else { return }
        let controller = PrompterController.shared
        let anchor = controller.readingAnchor
        let index = controller.layout.lineIndex(for: anchor)
        if liveHeader.prompterLinesView.isHidden {
            applyPrompterLiveHeader()
            return
        }
        guard index != liveHeader.prompterLinesView.lineIndex else { return }
        let around = controller.layout.lines(around: anchor)
        liveHeader.applyPrompterLines(
            around.lines, currentIndex: around.currentIndex, lineIndex: index, isPlaying: controller.isPlaying
        )
    }

    private func updateVisiblePrompterTile() {
        guard let showsSection = sectionIndex(for: .shows) else { return }
        for (index, row) in openShowGridItems.enumerated() {
            guard case .prompter(_, let scriptId) = row,
                  let cell = collectionView.cellForItem(
                    at: IndexPath(item: index, section: showsSection)
                  ) as? LibraryThumbnailCell
            else { continue }
            configurePrompterTile(cell, scriptId: scriptId, isLive: isShowGridItemLive(row))
        }
    }
}
