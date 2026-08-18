//
//  ImageViewController+CompanionAlbums.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Grid depth when phone Shows are mirrored as albums.
enum CompanionGridBrowse: Equatable {
    case root
    case album(id: String)
    case leftover
    case remote(id: String)
}

/// One tile on the album home grid.
enum AlbumHomeTile: Equatable {
    case companion(LibraryAlbumDTO)
    case leftover(count: Int)
    case remote(id: String, name: String, count: Int)
}

// MARK: - Companion album home

extension ImageViewController {

    /// Live library file names in display order.
    var companionLiveIds: [String] {
        (0..<dataSource.count).compactMap { index in
            dataSource.getPath(at: index).map { URL(fileURLWithPath: $0).lastPathComponent }
        }
    }

    var companionLiveIdSet: Set<String> { Set(companionLiveIds) }

    /// Shows-as-albums for the active Landscape / Vertical bucket.
    var displayCompanionAlbums: [LibraryAlbumDTO] {
        companionAlbumStore.displayAlbums(
            for: dataSource.activeLibraryMode,
            liveIds: companionLiveIdSet
        )
    }

    var leftoverLibraryIds: [String] {
        companionAlbumStore.leftoverIds(
            liveIds: companionLiveIds,
            for: dataSource.activeLibraryMode
        )
    }

    /// Album tiles replace the flat library when the phone has sent any Show.
    var usesAlbumHome: Bool { !displayCompanionAlbums.isEmpty }

    var isAlbumHomeRoot: Bool { usesAlbumHome && companionBrowse == .root }

    var albumHomeTitle: String {
        switch companionBrowse {
        case .root:
            return "Albums"
        case .album(let id):
            return displayCompanionAlbums.first { $0.id == id }?.name ?? "Album"
        case .leftover:
            return "Library"
        case .remote(let id):
            return albumStore.displayAlbums.first { $0.id == id }?.name ?? "Album"
        }
    }

    /// Home tiles: phone albums, leftover library, then hosted albums.
    func albumHomeTiles() -> [AlbumHomeTile] {
        var tiles: [AlbumHomeTile] = displayCompanionAlbums.map { .companion($0) }
        let leftover = leftoverLibraryIds
        if !leftover.isEmpty {
            tiles.append(.leftover(count: leftover.count))
        }
        for album in albumStore.displayAlbums {
            tiles.append(.remote(id: album.id, name: album.name, count: album.items.count))
        }
        return tiles
    }

    func observeCompanionAlbums() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCompanionAlbumsChanged),
            name: CompanionAlbumStore.didChangeNotification,
            object: nil
        )
    }

    @objc private func handleCompanionAlbumsChanged() {
        reconcileCompanionBrowse()
        guard isViewLoaded, isInGridMode else { return }
        if usesAlbumHome {
            emptyStateView.hide()
            gridView.isHidden = false
            gradientView.isHidden = false
            titleLabel.isHidden = false
        }
        titleLabel.text = usesAlbumHome ? albumHomeTitle : "Eclipse"
        gridView.reloadData()
    }

    /// Drops a stale drill-in after albums or the library bucket change.
    func reconcileCompanionBrowse() {
        guard usesAlbumHome else {
            companionBrowse = .root
            return
        }
        switch companionBrowse {
        case .root:
            break
        case .album(let id):
            if displayCompanionAlbums.contains(where: { $0.id == id }) { return }
            companionBrowse = .root
        case .leftover:
            if leftoverLibraryIds.isEmpty { companionBrowse = .root }
        case .remote(let id):
            if albumStore.displayAlbums.contains(where: { $0.id == id }) { return }
            companionBrowse = .root
        }
    }

    func popCompanionAlbumHome() -> Bool {
        guard usesAlbumHome, companionBrowse != .root, isInGridMode else { return false }
        companionBrowse = .root
        titleLabel.text = "Albums"
        gridView.reloadData()
        setNeedsFocusUpdate()
        return true
    }

    func applyCompanionBrowse(forPlayingId id: String) {
        guard usesAlbumHome else { return }
        if let album = companionAlbumStore.album(
            containing: id,
            mode: dataSource.activeLibraryMode,
            liveIds: companionLiveIdSet
        ) {
            companionBrowse = .album(id: album.id)
        } else if leftoverLibraryIds.contains(id) {
            companionBrowse = .leftover
        }
        titleLabel.text = albumHomeTitle
    }

    // MARK: - Collection

    func companionNumberOfItems() -> Int? {
        guard usesAlbumHome else { return nil }
        switch companionBrowse {
        case .root:
            return albumHomeTiles().count
        case .album(let id):
            return displayCompanionAlbums.first { $0.id == id }?.itemIds.count ?? 0
        case .leftover:
            return leftoverLibraryIds.count
        case .remote(let id):
            return albumStore.displayAlbums.first { $0.id == id }?.items.count ?? 0
        }
    }

    func dequeueCompanionCell(
        _ collectionView: UICollectionView,
        at indexPath: IndexPath
    ) -> UICollectionViewCell? {
        guard usesAlbumHome else { return nil }
        if isAlbumHomeRoot {
            return dequeueAlbumFolderCell(collectionView, at: indexPath)
        }
        return dequeueCompanionItemCell(collectionView, at: indexPath)
    }

    func selectCompanionItem(at indexPath: IndexPath) -> Bool {
        guard usesAlbumHome, !isMoveMode, !isIgnoringSelectionEvents else {
            return usesAlbumHome && isMoveMode
        }
        if isAlbumHomeRoot {
            openAlbumHomeTile(at: indexPath.item)
            return true
        }
        playCompanionBrowsedItem(at: indexPath.item)
        return true
    }

    func companionPreferredFocusIndexPath() -> IndexPath? {
        guard usesAlbumHome, let count = companionNumberOfItems(), count > 0 else {
            return nil
        }
        return IndexPath(item: 0, section: 0)
    }
}

// MARK: - Private helpers

private extension ImageViewController {

    func dequeueAlbumFolderCell(
        _ collectionView: UICollectionView,
        at indexPath: IndexPath
    ) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: AlbumFolderCell.reuseId, for: indexPath
        ) as? AlbumFolderCell else {
            return UICollectionViewCell()
        }
        let tiles = albumHomeTiles()
        guard tiles.indices.contains(indexPath.item) else { return cell }
        cell.tag = indexPath.item
        switch tiles[indexPath.item] {
        case .companion(let album):
            cell.configure(title: album.name, count: album.itemIds.count, cover: nil)
            fillCover(on: cell, item: indexPath.item, path: pathForLibraryId(album.resolvedCoverId))
        case .leftover(let count):
            cell.configure(title: "Library", count: count, cover: nil)
            fillCover(on: cell, item: indexPath.item, path: pathForLibraryId(leftoverLibraryIds.first))
        case .remote(let id, let name, let count):
            cell.configure(title: name, count: count, cover: nil)
            let path = albumStore.displayAlbums.first { $0.id == id }?.items.first?.thumbnailSourcePath
            fillCover(on: cell, item: indexPath.item, path: path)
        }
        return cell
    }

    func dequeueCompanionItemCell(
        _ collectionView: UICollectionView,
        at indexPath: IndexPath
    ) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: "ThumbnailCell", for: indexPath
        ) as? ImageThumbnailCell else {
            return UICollectionViewCell()
        }
        switch companionBrowse {
        case .remote(let id):
            if let albumIndex = albumStore.displayAlbumIndex(forId: id) {
                configureAlbumCell(cell, albumIndex: albumIndex, itemIndex: indexPath.item)
            }
        case .album(let albumId):
            let ids = displayCompanionAlbums.first { $0.id == albumId }?.itemIds ?? []
            configureLibraryItemCell(cell, fileName: ids[safe: indexPath.item], at: indexPath)
        case .leftover:
            configureLibraryItemCell(
                cell, fileName: leftoverLibraryIds[safe: indexPath.item], at: indexPath
            )
        case .root:
            break
        }
        cell.isSelected = false
        return cell
    }

    func configureLibraryItemCell(
        _ cell: ImageThumbnailCell,
        fileName: String?,
        at indexPath: IndexPath
    ) {
        guard let fileName,
              let index = libraryIndex(forItemId: fileName),
              let path = dataSource.getPath(at: index) else { return }
        let media = MediaItem(path: path)
        cell.tag = indexPath.item
        cell.configure(with: nil, isVideo: media.isVideo)
        let size = (gridView.collectionViewLayout as? UICollectionViewFlowLayout)?
            .itemSize ?? CGSize(width: 300, height: 169)
        cell.configureAsync(
            imagePath: media.path, isVideo: media.isVideo, cellSize: size, userPosition: nil
        )
    }

    func openAlbumHomeTile(at index: Int) {
        let tiles = albumHomeTiles()
        guard tiles.indices.contains(index) else { return }
        switch tiles[index] {
        case .companion(let album):
            companionBrowse = .album(id: album.id)
        case .leftover:
            companionBrowse = .leftover
        case .remote(let id, _, _):
            companionBrowse = .remote(id: id)
        }
        titleLabel.text = albumHomeTitle
        gridView.reloadData()
        setNeedsFocusUpdate()
    }

    func playCompanionBrowsedItem(at index: Int) {
        switch companionBrowse {
        case .remote(let id):
            guard let albumIndex = albumStore.displayAlbumIndex(forId: id),
                  index < albumStore.itemCount(albumIndex: albumIndex) else { return }
            activeCollection = .album
            albumCurrentAlbumIndex = albumIndex
            albumCurrentItemIndex = index
            rememberAlbumCursor()
            hideGridView()
        case .album(let albumId):
            let ids = displayCompanionAlbums.first { $0.id == albumId }?.itemIds ?? []
            playLibraryFile(named: ids[safe: index])
        case .leftover:
            playLibraryFile(named: leftoverLibraryIds[safe: index])
        case .root:
            break
        }
    }

    func playLibraryFile(named fileName: String?) {
        guard let fileName, let index = libraryIndex(forItemId: fileName) else { return }
        activeCollection = .library
        dataSource.setCurrentIndex(index)
        hideGridView()
    }

    func pathForLibraryId(_ id: String?) -> String? {
        guard let id, let index = libraryIndex(forItemId: id) else { return nil }
        return dataSource.getPath(at: index)
    }

    func fillCover(on cell: AlbumFolderCell, item: Int, path: String?) {
        guard let path else { return }
        let size = CGSize(width: 480, height: 270)
        let isVideo = ["mp4", "mov"].contains(URL(fileURLWithPath: path).pathExtension.lowercased())
        Task {
            let image: UIImage?
            if isVideo {
                image = await VideoThumbnailCache.shared.getThumbnailAsync(
                    for: path, targetSize: size
                )
            } else {
                image = await AsyncImageLoader.shared.loadImage(from: path, targetSize: size)
            }
            await MainActor.run {
                guard cell.tag == item, let image else { return }
                cell.setCover(image)
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
