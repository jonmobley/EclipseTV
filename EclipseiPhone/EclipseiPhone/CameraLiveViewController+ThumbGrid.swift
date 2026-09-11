//
//  CameraLiveViewController+ThumbGrid.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Thumbnail Grid (stacked layout)

extension CameraLiveViewController {

    /// Builds the Show-style thumbnail grid (called from `viewDidLoad`).
    func setupThumbGrid() {
        thumbGridView.dataSource = self
        thumbGridView.delegate = self
        thumbGridView.register(
            CameraStillRibbonCell.self,
            forCellWithReuseIdentifier: CameraStillRibbonCell.reuseId
        )
        thumbGridView.register(
            CameraFrameRibbonCell.self,
            forCellWithReuseIdentifier: CameraFrameRibbonCell.reuseId
        )
        thumbGridView.register(
            CameraProgramGridCell.self,
            forCellWithReuseIdentifier: CameraProgramGridCell.reuseId
        )
        view.addSubview(thumbGridView)
        let longPress = UILongPressGestureRecognizer(
            target: self,
            action: #selector(thumbGridLongPressed(_:))
        )
        thumbGridView.addGestureRecognizer(longPress)
    }

    /// Program, enabled frames, then Background · quick-change stills · +.
    var thumbGridItems: [CameraThumbGridItem] {
        Self.thumbGridItems(
            showsProgram: Self.showsLiveOutputThumb(
                isConnected: ExternalDisplayManager.shared.isConnected
            ),
            frameIds: CameraFrameStore.shared.enabledFrames.map(\.id),
            stills: stillRibbonItems
        )
    }

    // MARK: Layout

    /// Routes thumbnails to the grid band (stacked) or the in-panel ribbons.
    ///
    /// Stacked hides the ribbons outright: `layoutFrameRibbon` and
    /// `layoutLiveOutputThumb` set their own visibility, so they must not run.
    func layoutThumbnails(panel: CGRect) {
        if let stacked = stackedLayout {
            liveOutputThumbView.isHidden = true
            stillRibbonView.isHidden = true
            frameRibbonView.isHidden = true
            layoutThumbGrid(in: stacked.grid)
            return
        }
        thumbGridView.isHidden = true
        stillRibbonView.isHidden = false
        layoutLiveOutputThumb(panel: panel)
        layoutStillRibbon(panel: panel)
        layoutFrameRibbon(panel: panel)
    }

    /// Fills the grid band with Show-sized tiles on the Show's column grid.
    private func layoutThumbGrid(in band: CGRect) {
        thumbGridView.isHidden = false
        thumbGridView.frame = band
        if let layout = thumbGridView.collectionViewLayout as? UICollectionViewFlowLayout {
            let inset = Self.thumbGridSectionInset
            layout.itemSize = Self.thumbGridTileSize(
                width: band.width,
                orientation: ExternalOutputSettings.orientation
            )
            layout.minimumInteritemSpacing = Self.thumbGridSpacing
            layout.minimumLineSpacing = Self.thumbGridSpacing
            layout.sectionInset = UIEdgeInsets(
                top: 0, left: inset, bottom: inset, right: inset
            )
        }
        view.bringSubviewToFront(thumbGridView)
    }

    // MARK: Data Source Hooks

    func thumbGridItemCount() -> Int {
        thumbGridItems.count
    }

    /// Dequeues and fills the tile for one grid item.
    func thumbGridCell(at indexPath: IndexPath) -> UICollectionViewCell {
        let items = thumbGridItems
        guard items.indices.contains(indexPath.item) else { return UICollectionViewCell() }
        let radius = Self.thumbGridCornerRadius
        switch items[indexPath.item] {
        case .program:
            guard let cell = thumbGridView.dequeueReusableCell(
                withReuseIdentifier: CameraProgramGridCell.reuseId,
                for: indexPath
            ) as? CameraProgramGridCell else { return UICollectionViewCell() }
            configureLiveOutputThumb(cell.thumbView)
            cell.thumbView.layer.cornerRadius = radius
            cell.mirrorThumbAccessibility()
            return cell
        case .frame(let id):
            guard let cell = thumbGridView.dequeueReusableCell(
                withReuseIdentifier: CameraFrameRibbonCell.reuseId,
                for: indexPath
            ) as? CameraFrameRibbonCell else { return UICollectionViewCell() }
            let store = CameraFrameStore.shared
            cell.configure(image: store.image(for: id), isLive: store.selectedId == id)
            cell.applyCornerRadius(radius)
            return cell
        case .still(let item):
            guard let cell = thumbGridView.dequeueReusableCell(
                withReuseIdentifier: CameraStillRibbonCell.reuseId,
                for: indexPath
            ) as? CameraStillRibbonCell else { return UICollectionViewCell() }
            configureStillRibbonCell(cell, item: item)
            cell.applyCornerRadius(radius)
            return cell
        }
    }

    /// Same actions as the ribbons; the program monitor is display-only.
    func handleThumbGridTap(at indexPath: IndexPath) {
        let items = thumbGridItems
        guard items.indices.contains(indexPath.item) else { return }
        switch items[indexPath.item] {
        case .program:
            break
        case .frame(let id):
            toggleFrameOverlay(id)
        case .still(let item):
            handleStillRibbonItemTap(item)
        }
    }

    /// Hold a quick-change tile for Replace / Remove, as on the ribbon.
    @objc func thumbGridLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let point = gesture.location(in: thumbGridView)
        guard let indexPath = thumbGridView.indexPathForItem(at: point) else { return }
        let items = thumbGridItems
        guard items.indices.contains(indexPath.item),
              case .still(.cutaway(let id)) = items[indexPath.item]
        else { return }
        presentCutawayActions(id: id, anchor: thumbGridView.cellForItem(at: indexPath))
    }
}

// MARK: - Program Grid Cell

/// Grid tile hosting the program monitor thumb.
final class CameraProgramGridCell: UICollectionViewCell {
    static let reuseId = "CameraProgramGridCell"

    let thumbView = CameraLiveOutputThumbView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        thumbView.isHidden = false
        thumbView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(thumbView)
        NSLayoutConstraint.activate([
            thumbView.topAnchor.constraint(equalTo: contentView.topAnchor),
            thumbView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            thumbView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            thumbView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The thumb is not interactive, so the cell speaks for it.
    func mirrorThumbAccessibility() {
        isAccessibilityElement = true
        accessibilityLabel = thumbView.accessibilityLabel
        accessibilityValue = thumbView.accessibilityValue
        accessibilityTraits = .image
    }
}
