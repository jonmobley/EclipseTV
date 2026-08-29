//
//  CameraLiveViewController+FrameRibbon.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Camera Frame Ribbon

extension CameraLiveViewController: UICollectionViewDataSource, UICollectionViewDelegate {

    /// Builds the overlay-frame thumbnail strip beside the cutaway still.
    func setupFrameRibbon() {
        frameRibbonView.dataSource = self
        frameRibbonView.delegate = self
        frameRibbonView.register(
            CameraFrameRibbonCell.self,
            forCellWithReuseIdentifier: CameraFrameRibbonCell.reuseId
        )
        view.addSubview(frameRibbonView)
        reloadFrameRibbon()
    }

    /// Packs the ribbon against the stills ribbon, same thumb size and 8pt gap.
    func layoutFrameRibbon(panel: CGRect) {
        let frames = CameraFrameStore.shared.enabledFrames
        frameRibbonView.isHidden = frames.isEmpty
        guard !frames.isEmpty else { return }

        let thumb = stillRibbonThumbSize()
        guard thumb.width > 1, thumb.height > 1 else { return }
        applyFrameRibbonItemSize(thumb)

        let gap: CGFloat = 8
        let maxX = stillRibbonView.frame.minX - gap
        let available = max(0, maxX - frameRibbonLeadingMinX(panel: panel, gap: gap))
        let count = CGFloat(frames.count)
        let contentWidth = count * thumb.width + max(0, count - 1) * gap
        let width = min(contentWidth, available)
        frameRibbonView.frame = CGRect(
            x: maxX - width,
            y: stillRibbonView.frame.minY,
            width: width,
            height: thumb.height
        )
        frameRibbonView.contentInset = .zero
        view.bringSubviewToFront(frameRibbonView)
    }

    /// Matches ribbon cells to the cutaway thumb, with the same spacing.
    private func applyFrameRibbonItemSize(_ thumb: CGSize) {
        guard let layout = frameRibbonView.collectionViewLayout
            as? UICollectionViewFlowLayout else { return }
        layout.itemSize = thumb
        layout.minimumLineSpacing = 8
        layout.minimumInteritemSpacing = 8
    }

    /// Ribbon may grow left to the program thumb, or the panel inset.
    private func frameRibbonLeadingMinX(panel: CGRect, gap: CGFloat) -> CGFloat {
        if !liveOutputThumbView.isHidden, liveOutputThumbView.bounds.width > 1 {
            return liveOutputThumbView.frame.maxX + gap
        }
        return panel.minX + cameraThumbEdgeInset(panel: panel)
    }

    /// Reloads ribbon thumbs after the library or live overlay changes.
    func reloadFrameRibbon() {
        frameRibbonView.reloadData()
        layoutFrameRibbon(panel: panelView.convert(panelView.bounds, to: view))
    }

    func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        if collectionView === stillRibbonView {
            return stillRibbonItems.count
        }
        guard collectionView === frameRibbonView else { return 0 }
        return CameraFrameStore.shared.enabledFrames.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        if collectionView === stillRibbonView {
            return stillRibbonCell(at: indexPath)
        }
        guard collectionView === frameRibbonView,
              let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: CameraFrameRibbonCell.reuseId,
                for: indexPath
              ) as? CameraFrameRibbonCell else {
            return UICollectionViewCell()
        }
        let store = CameraFrameStore.shared
        let frames = store.enabledFrames
        guard frames.indices.contains(indexPath.item) else { return cell }
        let frame = frames[indexPath.item]
        cell.configure(
            image: store.image(for: frame.id),
            isLive: store.selectedId == frame.id
        )
        return cell
    }

    func collectionView(
        _ collectionView: UICollectionView,
        didSelectItemAt indexPath: IndexPath
    ) {
        collectionView.deselectItem(at: indexPath, animated: false)
        if collectionView === stillRibbonView {
            handleStillRibbonTap(at: indexPath)
            return
        }
        guard collectionView === frameRibbonView else { return }
        let store = CameraFrameStore.shared
        let frames = store.enabledFrames
        guard frames.indices.contains(indexPath.item) else { return }
        let id = frames[indexPath.item].id
        store.select(store.selectedId == id ? nil : id)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Configures a Background / quick-change / add cell for the stills ribbon.
    func stillRibbonCell(at indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = stillRibbonView.dequeueReusableCell(
            withReuseIdentifier: CameraStillRibbonCell.reuseId,
            for: indexPath
        ) as? CameraStillRibbonCell else {
            return UICollectionViewCell()
        }
        let items = stillRibbonItems
        guard items.indices.contains(indexPath.item) else { return cell }
        configureStillRibbonCell(cell, item: items[indexPath.item])
        return cell
    }

    func configureStillRibbonCell(
        _ cell: CameraStillRibbonCell,
        item: CameraStillRibbonItem
    ) {
        let parked = ExternalDisplayManager.shared.parkedCameraStill
        switch item {
        case .background:
            cell.configure(
                image: LogoStore.shared.image,
                symbolName: LogoStore.shared.image == nil ? "photo" : nil,
                isLive: parked == .background,
                accessibilityLabel: "Background",
                accessibilityHint: parked == .background
                    ? "Background is live. Tap to return to the live camera."
                    : "Tap to show the Show Background on program."
            )
        case .cutaway(let id):
            let live = parked == .cutaway(id)
            cell.configure(
                image: CameraAlternateStillStore.shared.image(for: id),
                symbolName: "photo",
                isLive: live,
                accessibilityLabel: "Quick Change",
                accessibilityHint: live
                    ? "Quick Change is live. Tap to return to the live camera."
                    : "Tap to show this photo on program. Hold to replace or remove."
            )
        case .add:
            cell.configure(
                image: nil,
                symbolName: "plus",
                isLive: false,
                accessibilityLabel: "Add Quick Change",
                accessibilityHint: "Adds another still to select while camera is open"
            )
        }
    }
}

// MARK: - Ribbon Cell

final class CameraFrameRibbonCell: UICollectionViewCell {
    static let reuseId = "CameraFrameRibbonCell"

    private let imageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.backgroundColor = UIColor(white: 0.12, alpha: 1)
        view.clipsToBounds = true
        view.layer.cornerRadius = 10
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(image: UIImage?, isLive: Bool) {
        imageView.image = image
        imageView.layer.borderWidth = isLive ? 3 : 1
        imageView.layer.borderColor = isLive
            ? UIColor.systemBlue.cgColor
            : UIColor.white.withAlphaComponent(0.35).cgColor
        accessibilityLabel = "Frame overlay"
        accessibilityValue = isLive ? "On camera" : "Off"
        accessibilityHint = isLive
            ? "Tap to hide this overlay"
            : "Tap to show this overlay on the camera"
    }
}
