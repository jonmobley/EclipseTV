// ImageViewController+Album.swift
import UIKit
import AVFoundation
import Combine
import os.log

/// Which collection the fullscreen viewer is acting on. The local library is backed by
/// `MediaDataSource`; albums are backed by `RemoteAlbumStore`.
enum CollectionKind {
    case library
    case album
}

// MARK: - Remote Album Integration

extension ImageViewController {

    /// Grid section index for the local (iPhone-managed) library. Album sections follow
    /// at indices 1…N (one per non-empty album in `albumStore.displayAlbums`).
    static let librarySectionIndex = 0

    // MARK: - Setup & Sync

    /// Observes album changes and kicks off an initial sync if an account is configured.
    /// Call once during view setup.
    func setupAlbumSync() {
        albumStore.$albums
            .receive(on: DispatchQueue.main)
            .dropFirst()
            .sink { [weak self] _ in
                self?.handleAlbumItemsChanged()
            }
            .store(in: &cancellables)

        refreshAlbumIfConfigured()

        #if DEBUG
        maybeAutoloadDemoAlbum()
        #endif
    }

    #if DEBUG
    private static let demoAutoloadedKey = "EclipseTV.album.demoAutoloaded"

    /// On the first debug launch with no album configured, auto-loads the demo album so
    /// the feature can be tested with zero setup. Use "Remove Album" then relaunch (or
    /// reset the flag) to see it again.
    func maybeAutoloadDemoAlbum() {
        guard !albumStore.hasAlbumConfigured, albumStore.isEmpty else { return }
        guard !UserDefaults.standard.bool(forKey: Self.demoAutoloadedKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.demoAutoloadedKey)
        logger.info("Auto-loading demo album on first debug launch")
        loadDemoAlbum()
    }
    #endif

    /// Loads the built-in demo album, showing progress/result toasts.
    func loadDemoAlbum() {
        showNotificationToast(message: "Loading demo album…")
        Task { [weak self] in
            do {
                let count = try await RemoteAlbumSync.shared.loadDemo()
                await MainActor.run {
                    self?.showNotificationToast(message: "Demo album loaded (\(count) item\(count == 1 ? "" : "s"))")
                }
            } catch {
                await MainActor.run {
                    self?.showNotificationToast(message: "Demo album failed to load")
                }
            }
        }
    }

    /// Triggers a background sync against the configured manifest URL, if any.
    func refreshAlbumIfConfigured() {
        guard albumStore.hasAlbumConfigured else { return }
        Task { [weak self] in
            do {
                let count = try await RemoteAlbumSync.shared.sync()
                await MainActor.run {
                    self?.logger.info("Album sync finished with \(count) item(s)")
                }
            } catch {
                await MainActor.run {
                    self?.logger.error("Album sync failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    /// Reflects album content changes in the grid, revealing it if the empty state was
    /// only showing because the local library was empty.
    func handleAlbumItemsChanged() {
        reconcileAlbumCursor()
        guard isViewLoaded, isInGridMode else { return }

        if dataSource.isEmpty && albumStore.totalItemCount > 0 {
            emptyStateView.hide()
            gridView.isHidden = false
            gradientView.isHidden = false
            titleLabel.isHidden = false
        }

        gridView.reloadData()
        DispatchQueue.main.async {
            self.simpleSelectionManager.validateSelectionState()
        }
    }

    // MARK: - Album Cursor (identity-tracked)

    /// Records the active album cursor as stable ids, so a later sync can restore the
    /// position even if albums/items were reordered or removed. Call after any change to
    /// `albumCurrentAlbumIndex` / `albumCurrentItemIndex`.
    func rememberAlbumCursor() {
        albumCurrentAlbumId = albumStore.album(at: albumCurrentAlbumIndex)?.id
        albumCurrentItemId = albumStore.item(albumIndex: albumCurrentAlbumIndex,
                                             itemIndex: albumCurrentItemIndex)?.id
    }

    /// Re-resolves the cursor indices from the remembered ids after the album set changes
    /// (e.g. a background sync that reordered or deleted albums/items). Falls back to
    /// bounds-clamping when the remembered album/item no longer exists, then re-syncs ids.
    func reconcileAlbumCursor() {
        if let albumId = albumCurrentAlbumId,
           let albumIndex = albumStore.displayAlbumIndex(forId: albumId) {
            albumCurrentAlbumIndex = albumIndex
            if let itemId = albumCurrentItemId,
               let itemIndex = albumStore.itemIndex(inAlbumIndex: albumIndex, forId: itemId) {
                albumCurrentItemIndex = itemIndex
            } else {
                // Item removed: stay in the same album, clamped to its current bounds.
                albumCurrentItemIndex = clamp(albumCurrentItemIndex,
                                              max: albumStore.itemCount(albumIndex: albumIndex))
            }
        } else {
            // Album removed (or nothing remembered): clamp both to bounds.
            albumCurrentAlbumIndex = clamp(albumCurrentAlbumIndex, max: albumStore.albumSectionCount)
            albumCurrentItemIndex = clamp(albumCurrentItemIndex,
                                          max: albumStore.itemCount(albumIndex: albumCurrentAlbumIndex))
        }
        rememberAlbumCursor()
    }

    /// Clamps `index` into `0..<count` (or 0 when empty).
    private func clamp(_ index: Int, max count: Int) -> Int {
        min(max(0, index), max(0, count - 1))
    }

    // MARK: - Fullscreen Display Routing

    /// The file path of the item currently shown (or to be shown) fullscreen, resolved
    /// against whichever collection is active.
    func currentDisplayPath() -> String? {
        switch activeCollection {
        case .library: return dataSource.getCurrentPath()
        case .album: return albumStore.path(albumIndex: albumCurrentAlbumIndex, itemIndex: albumCurrentItemIndex)
        }
    }

    /// Advances within the active collection. Album navigation stays inside the current
    /// album. Returns false at the end.
    @discardableResult
    func advanceDisplayIndex() -> Bool {
        switch activeCollection {
        case .library:
            return dataSource.nextIndex()
        case .album:
            let itemCount = albumStore.itemCount(albumIndex: albumCurrentAlbumIndex)
            guard albumCurrentItemIndex < itemCount - 1 else { return false }
            albumCurrentItemIndex += 1
            rememberAlbumCursor()
            return true
        }
    }

    /// Steps back within the active collection (album navigation stays inside the current
    /// album). Returns false at the start.
    @discardableResult
    func retreatDisplayIndex() -> Bool {
        switch activeCollection {
        case .library:
            return dataSource.previousIndex()
        case .album:
            guard albumCurrentItemIndex > 0 else { return false }
            albumCurrentItemIndex -= 1
            rememberAlbumCursor()
            return true
        }
    }

    // MARK: - Album Cell Configuration

    /// Configures a thumbnail cell for a read-only album item at `itemIndex` within the
    /// display album `albumIndex`. Unlike library cells, no long-press gesture is added.
    func configureAlbumCell(_ cell: ImageThumbnailCell, albumIndex: Int, itemIndex: Int) {
        cell.gestureRecognizers?.forEach { gesture in
            if gesture is UILongPressGestureRecognizer { cell.removeGestureRecognizer(gesture) }
        }
        cell.tag = itemIndex

        guard let item = albumStore.item(albumIndex: albumIndex, itemIndex: itemIndex) else {
            cell.configure(with: nil, isVideo: false)
            return
        }

        cell.configure(with: nil, isVideo: item.isVideo)
        let cellSize = (gridView.collectionViewLayout as? UICollectionViewFlowLayout)?.itemSize
            ?? CGSize(width: 300, height: 169)
        cell.configureAsync(imagePath: item.localPath, isVideo: item.isVideo, cellSize: cellSize, userPosition: nil)

        if item.isVideo {
            let path = item.localPath
            let section = albumIndex + 1
            Task {
                let duration = await ImageViewController.albumVideoDuration(for: path)
                await MainActor.run {
                    let indexPath = IndexPath(item: itemIndex, section: section)
                    if let visible = self.gridView.cellForItem(at: indexPath) as? ImageThumbnailCell,
                       visible.tag == itemIndex {
                        visible.configure(with: visible.currentImage, isVideo: true,
                                          duration: duration, isLooping: false, isMuted: false)
                    }
                }
            }
        }
    }

    private static func albumVideoDuration(for path: String) async -> TimeInterval {
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        do {
            let duration = try await asset.load(.duration)
            return duration.seconds.isFinite ? duration.seconds : 0
        } catch {
            return 0
        }
    }

    // MARK: - Code Entry

    /// Prompts for the account code directly on the TV (no companion required), stores
    /// it, and kicks off a sync. Pre-fills the field with any existing code so it doubles
    /// as an "edit" flow.
    func presentAccountCodeEntry() {
        let alert = UIAlertController(
            title: "Enter Account Code",
            message: "Type your \(AlbumConfig.codeLength)-digit account code to sync your albums.",
            preferredStyle: .alert)

        alert.addTextField { [weak self] field in
            field.placeholder = String(repeating: "0", count: AlbumConfig.codeLength)
            field.keyboardType = .numberPad
            field.textContentType = .oneTimeCode
            field.text = self?.albumStore.accountCode
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Sync Albums", style: .default) { [weak self, weak alert] _ in
            guard let self = self else { return }
            let raw = alert?.textFields?.first?.text ?? ""
            guard self.albumStore.setAccountCode(raw) else {
                self.showNotificationToast(message: "Enter a valid \(AlbumConfig.codeLength)-digit code")
                return
            }
            self.showNotificationToast(message: "Account code saved — syncing…")
            self.refreshAlbumFromMenu()
        })

        present(alert, animated: true)
    }

    // MARK: - Menu Actions

    /// Manually syncs the account's albums, showing a toast with the result (or the
    /// server-provided reason on failure, e.g. an unknown code).
    func refreshAlbumFromMenu() {
        guard albumStore.hasAlbumConfigured else {
            showNotificationToast(message: "No account configured")
            return
        }
        showNotificationToast(message: "Syncing albums…")
        Task { [weak self] in
            do {
                let count = try await RemoteAlbumSync.shared.sync()
                await MainActor.run {
                    self?.showNotificationToast(message: "Albums synced (\(count) item\(count == 1 ? "" : "s"))")
                }
            } catch {
                await MainActor.run {
                    self?.showNotificationToast(message: error.localizedDescription)
                }
            }
        }
    }
}
