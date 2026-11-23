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
        installFramePresetLongPress()
        reloadFrameRibbon()
    }

    /// Packs the ribbon against the stills ribbon, same thumb size and 8pt gap.
    func layoutFrameRibbon(panel: CGRect) {
        let frames = frameRibbonEntries
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

    /// Reloads frame thumbs (ribbon and grid) after the library or live overlay changes.
    func reloadFrameRibbon() {
        frameRibbonView.reloadData()
        thumbGridView.reloadData()
        layoutThumbnails(panel: panelView.convert(panelView.bounds, to: view))
    }

    /// Tap toggles the overlay on the camera; tapping the live one turns it off.
    func toggleFrameOverlay(_ id: UUID) {
        let store = CameraFrameStore.shared
        CameraKitStore.shared.clearFrameSelection()
        store.select(store.selectedId == id ? nil : id)
        Haptics.impactLight()
    }

    func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        if collectionView === stillRibbonView {
            return stillRibbonItems.count
        }
        if collectionView === thumbGridView {
            return thumbGridItemCount()
        }
        guard collectionView === frameRibbonView else { return 0 }
        return frameRibbonEntries.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        if collectionView === stillRibbonView {
            return stillRibbonCell(at: indexPath)
        }
        if collectionView === thumbGridView {
            return thumbGridCell(at: indexPath)
        }
        guard collectionView === frameRibbonView,
              let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: CameraFrameRibbonCell.reuseId,
                for: indexPath
              ) as? CameraFrameRibbonCell else {
            return UICollectionViewCell()
        }
        let entries = frameRibbonEntries
        guard entries.indices.contains(indexPath.item) else { return cell }
        let entry = entries[indexPath.item]
        cell.configure(image: pictureImage(entry), isOn: pictureIsLive(entry), isFrame: entry.isFrame)
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
        if collectionView === thumbGridView {
            handleThumbGridTap(at: indexPath)
            return
        }
        guard collectionView === frameRibbonView else { return }
        let entries = frameRibbonEntries
        guard entries.indices.contains(indexPath.item) else { return }
        toggleFrameEntry(entries[indexPath.item])
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
                image: CameraAlternateStillStore.shared.image(for: id)
                    ?? CameraKitStore.shared.image(for: id),
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

// MARK: - Frame "ON" Badge

/// Marks a frame that is switched on over the camera picture.
///
/// Frames never take the blue outline: blue means "on the TV", and a frame is
/// only a layer on the camera, which may not be on the TV at all (2026-11-23).
final class CameraFrameOnBadge: UIView {
    private let iconView = UIImageView()
    private let label = UILabel()
    private let stack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.black.withAlphaComponent(0.65)
        layer.cornerCurve = .continuous
        isUserInteractionEnabled = false
        let config = UIImage.SymbolConfiguration(pointSize: 10, weight: .bold)
        iconView.image = UIImage(systemName: "checkmark", withConfiguration: config)
        iconView.tintColor = .white
        iconView.contentMode = .scaleAspectFit
        label.text = "ON"
        label.font = .systemFont(ofSize: 11, weight: .bold)
        label.textColor = .white
        stack.axis = .horizontal
        stack.spacing = 3
        stack.alignment = .center
        stack.addArrangedSubview(iconView)
        stack.addArrangedSubview(label)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Small ribbon thumbs show the check only; the word needs a Show-sized tile.
    func setCompact(_ compact: Bool) {
        label.isHidden = compact
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }

    /// Adds a hidden badge to the top-leading corner of `host`.
    static func install(in host: UIView, inset: CGFloat = 6) -> CameraFrameOnBadge {
        let badge = CameraFrameOnBadge()
        badge.isHidden = true
        badge.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(badge)
        NSLayoutConstraint.activate([
            badge.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: inset),
            badge.topAnchor.constraint(equalTo: host.topAnchor, constant: inset),
            badge.heightAnchor.constraint(equalToConstant: 20)
        ])
        return badge
    }
}

// MARK: - Ribbon Cell

final class CameraFrameRibbonCell: UICollectionViewCell {
    static let reuseId = "CameraFrameRibbonCell"

    private let imageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        // Dark checks show which parts of the frame are see-through.
        view.backgroundColor = .transparencyCheckerboard
        view.clipsToBounds = true
        view.layer.cornerRadius = 10
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    /// ⋯ on Show-sized grid tiles only; hidden on the small in-panel ribbon.
    private lazy var moreButton = CameraTileMoreButton.install(in: contentView)

    /// "✓ ON" on a frame that is switched on over the camera.
    private lazy var onBadge = CameraFrameOnBadge.install(in: contentView)

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

    override func prepareForReuse() {
        super.prepareForReuse()
        setMoreMenu(nil)
    }

    /// Shows the ⋯ menu (`nil` hides it).
    func setMoreMenu(_ menu: UIMenu?) {
        CameraTileMoreButton.set(menu, on: moreButton)
    }

    /// Ribbon thumbs are 10pt; Show-sized grid tiles take the Show card radius.
    func applyCornerRadius(_ radius: CGFloat) {
        imageView.layer.cornerRadius = radius
        imageView.layer.cornerCurve = .continuous
    }

    /// Shows a tile. Frames sit on a dark checkerboard so see-through areas show.
    ///
    /// - Parameter isOn: for a frame, switched on over the camera (shown with the
    ///   ON badge, never the blue outline); for a picture, on the TV now (blue).
    func configure(image: UIImage?, isOn: Bool, isFrame: Bool = true) {
        imageView.image = image
        imageView.contentMode = isFrame ? .scaleAspectFit : .scaleAspectFill
        imageView.backgroundColor = isFrame ? .transparencyCheckerboard : .mediaPlaceholder
        let showsBlue = Self.showsLiveOutline(isOn: isOn, isFrame: isFrame)
        imageView.layer.borderWidth = showsBlue ? 3 : 1
        imageView.layer.borderColor = showsBlue
            ? UIColor.liveStroke.cgColor
            : UIColor.white.withAlphaComponent(0.35).cgColor
        onBadge.isHidden = !Self.showsOnBadge(isOn: isOn, isFrame: isFrame)
        contentView.bringSubviewToFront(onBadge)
        accessibilityLabel = isFrame ? "Frame overlay" : "Picture"
        if isFrame {
            accessibilityValue = isOn ? "On" : "Off"
            accessibilityHint = isOn
                ? "Tap to take this frame off the camera"
                : "Tap to put this frame on the camera"
        } else {
            accessibilityValue = isOn ? "On the TV" : "Off"
            accessibilityHint = isOn
                ? "Tap to go back to the camera"
                : "Tap to show this picture on the TV"
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        onBadge.setCompact(bounds.width < 100)
    }

    /// Blue is reserved for what the TV shows; a frame never gets it.
    static func showsLiveOutline(isOn: Bool, isFrame: Bool) -> Bool { isOn && !isFrame }

    /// A frame that is on gets the ON badge instead of an outline.
    static func showsOnBadge(isOn: Bool, isFrame: Bool) -> Bool { isOn && isFrame }
}
