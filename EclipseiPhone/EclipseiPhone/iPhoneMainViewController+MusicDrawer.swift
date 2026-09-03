//
//  iPhoneMainViewController+MusicDrawer.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Music drawer (regular width)

extension iPhoneMainViewController: UIGestureRecognizerDelegate {

    /// Installs the overlay and the right-edge pan that opens it.
    func setupMusicDrawer() {
        let drawer = musicDrawer
        drawer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(drawer)
        NSLayoutConstraint.activate([
            drawer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            drawer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            drawer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            drawer.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let edge = UIScreenEdgePanGestureRecognizer(
            target: self, action: #selector(handleMusicEdgePan(_:))
        )
        edge.edges = .right
        edge.delegate = self
        view.addGestureRecognizer(edge)
        musicEdgePanRecognizer = edge
    }

    /// Legacy pin API — regular width always uses the drawer; pinning is a no-op.
    func setMusicSidebarPinned(_ pinned: Bool, animated: Bool) {
        guard pinned != isMusicSidebarPinned else { return }
        isMusicSidebarPinned = pinned
        HomeMusicLayout.setPinned(pinned)
        if pinned {
            musicDrawer.setOpen(false, animated: false)
        }
        let apply = { [weak self] in
            guard let self else { return }
            self.updateHomeSplitLayoutIfNeeded()
            self.libraryViewController.invalidatePageLayouts()
            self.refreshLibraryMenu()
            self.view.layoutIfNeeded()
        }
        if animated, !UIAccessibility.isReduceMotionEnabled {
            UIView.animate(
                withDuration: 0.3,
                delay: 0,
                options: [.curveEaseInOut, .beginFromCurrentState]
            ) {
                apply()
            }
        } else {
            apply()
        }
    }

    /// Hosts Music in the pager or the floating drawer for `mode`.
    func updateMusicHost(for mode: HomeMusicLayout.Mode) {
        let useDrawer = mode == .drawer
        let musicView = audioLibraryNavController?.view
        let needsHost = musicView?.superview == nil || useDrawer != isMusicInDrawer
        if needsHost {
            isMusicInDrawer = useDrawer
            if useDrawer {
                installMusicInDrawer()
            } else {
                installMusicInPager()
            }
        }
        musicDrawer.isDrawerEnabled = useDrawer
        if useDrawer {
            musicDrawer.panelWidth = HomeMusicLayout.sidebarWidth(
                for: max(homePagerScrollView.bounds.width, 1)
            )
            raiseAudioMiniChrome()
        } else {
            musicDrawer.setOpen(false, animated: false)
        }
        audioLibraryViewController.showsEmbeddedBackButton = mode == .paging
        libraryViewController.setMusicPagingAvailable(mode == .paging)
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === musicEdgePanRecognizer else { return true }
        guard isMusicInDrawer, musicDrawer.progress < 0.95 else { return false }
        if libraryViewController.isArranging || libraryViewController.isSelecting {
            return false
        }
        let point = gestureRecognizer.location(in: musicDrawer)
        return !musicDrawer.containsTab(at: point)
    }

    @objc private func handleMusicEdgePan(_ gesture: UIScreenEdgePanGestureRecognizer) {
        if gesture.state == .began {
            raiseAudioMiniChrome()
        }
        musicDrawer.handleEdgePan(gesture)
    }

    // MARK: - Reparent Music

    private func installMusicInDrawer() {
        guard let musicView = audioLibraryNavController?.view else { return }
        NSLayoutConstraint.deactivate(musicPagerConstraints)
        musicPagerConstraints = []
        musicDrawer.embedContent(musicView)
        libraryTrailingToContentConstraint?.isActive = true
    }

    private func installMusicInPager() {
        guard let musicView = audioLibraryNavController?.view else { return }
        musicView.removeFromSuperview()
        musicView.translatesAutoresizingMaskIntoConstraints = false
        homePagerScrollView.addSubview(musicView)
        libraryTrailingToContentConstraint?.isActive = false
        activateMusicPagerConstraints(musicView: musicView)
    }

    private func activateMusicPagerConstraints(musicView: UIView) {
        let gridView = libraryViewController.view!
        let frame = homePagerScrollView.frameLayoutGuide
        let width = musicPageWidthConstraint
            ?? musicView.widthAnchor.constraint(equalToConstant: 320)
        musicPageWidthConstraint = width
        let constraints: [NSLayoutConstraint] = [
            musicView.topAnchor.constraint(
                equalTo: homePagerScrollView.contentLayoutGuide.topAnchor
            ),
            musicView.bottomAnchor.constraint(
                equalTo: homePagerScrollView.contentLayoutGuide.bottomAnchor
            ),
            musicView.leadingAnchor.constraint(equalTo: gridView.trailingAnchor),
            musicView.trailingAnchor.constraint(
                equalTo: homePagerScrollView.contentLayoutGuide.trailingAnchor
            ),
            width,
            musicView.heightAnchor.constraint(equalTo: frame.heightAnchor)
        ]
        musicPagerConstraints = constraints
        NSLayoutConstraint.activate(constraints)
    }
}
