//
//  LibraryGridViewController+Prompter.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

extension LibraryGridViewController {

    // MARK: - Operator view

    /// Opens the full-screen Prompter for the open Show. Never puts it live by itself.
    func presentPrompterOperator() {
        guard let showId = openShowId else { return }
        guard !isAlreadyOpen(PrompterViewController.self) else { return }
        let prompter = PrompterViewController(showId: showId)
        // A Show Live operator device drives nothing itself: it reads along and
        // edits the script (which syncs), but Go Live stays with the director.
        if !ShowLiveSession.shared.isRemoteOperator {
            prompter.liveActions = .init(
                goLive: { [weak self] in self?.presentPrompterLive() ?? false },
                stopLive: { [weak self] in self?.stopPrompterLive() }
            )
        }
        let nav = UINavigationController(rootViewController: prompter)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }

    /// Opens the script editor straight from the tile.
    func presentPrompterScriptEditor() {
        guard let showId = openShowId else { return }
        let nav = PrompterScriptEditorViewController.makeNavigation(
            showId: showId, traits: traitCollection, anchor: nil, arrows: []
        )
        topmostPresenter.present(nav, animated: true)
    }

    // MARK: - Live

    /// Puts the open Show's script on AirPlay / HDMI (or the Practice hero).
    /// Returns whether it went live.
    @discardableResult
    func presentPrompterLive() -> Bool {
        guard let showId = openShowId else { return false }
        guard ensurePrompterDestination() else { return false }
        guard !blockLiveChangeIfLocked() else { return false }
        isBlackSelected = false
        isLogoSelected = false
        isScreensaverSelected = false
        SlideshowPlaybackController.shared.stop()
        // Bind, then publish the overlay: `liveShowId` and `overlaySource` name the
        // same script before anything observing either of them repaints.
        PrompterController.shared.prepareLive(showId: showId)
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

    /// Configures the Show-grid Prompter tile.
    func configurePrompterTile(_ cell: LibraryThumbnailCell, isLive: Bool) {
        let script = openShowId.map { PrompterScriptStore.shared.script(forShowId: $0) } ?? ""
        cell.configurePrompter(
            excerpt: LibraryThumbnailCell.prompterExcerpt(from: script),
            isLive: isLive,
            isLocked: isLiveOutputLocked,
            isPlaying: isLive && PrompterController.shared.isPlaying
        )
    }

    /// ⋯ menu: open, go live, edit, reset, arrange, select, remove.
    func prompterContextMenu() -> UIMenu {
        let token = ShowToolToken.prompter
        let isLive = isShowGridItemLive(.prompter)
        var children: [UIMenuElement] = [
            UIAction(title: "Open", image: UIImage(systemName: "text.alignleft")) { [weak self] _ in
                self?.presentPrompterOperator()
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
                    attributes: PrompterScriptStore.shared.hasScript(forShowId: openShowId ?? UUID()) ? [] : .disabled
                ) { [weak self] _ in
                    self?.presentPrompterLive()
                })
            }
        }
        children.append(UIAction(title: "Edit Script", image: UIImage(systemName: "pencil")) { [weak self] _ in
            self?.presentPrompterScriptEditor()
        })
        children.append(UIAction(title: "Reset to Top", image: UIImage(systemName: "backward.end.fill")) { _ in
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
            guard case .prompter = row,
                  let cell = collectionView.cellForItem(
                    at: IndexPath(item: index, section: showsSection)
                  ) as? LibraryThumbnailCell
            else { continue }
            configurePrompterTile(cell, isLive: isShowGridItemLive(.prompter))
        }
    }
}
