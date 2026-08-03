//
//  SlideshowDetailViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Edits slideshow name, preferences, and ordered slides (images only).
final class SlideshowDetailViewController: UITableViewController {

    private enum Section: Int, CaseIterable {
        case preferences
        case slides
    }

    private let slideshowId: UUID
    private let slideReuseId = "slideshowSlideCell"
    private let prefReuseId = "slideshowPrefCell"

    private var slideshow: Slideshow? {
        SlideshowStore.shared.slideshow(id: slideshowId)
    }

    private var slides: [LibraryItemDTO] {
        guard let slideshow else { return [] }
        return slideshow.itemIds.compactMap { id in
            TVLibraryStore.shared.items.first(where: { $0.id == id && !$0.isVideo })
        }
    }

    /// Creates a detail screen for `slideshowId`.
    init(slideshowId: UUID) {
        self.slideshowId = slideshowId
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = slideshow?.name ?? "Slideshow"
        navigationItem.rightBarButtonItems = [
            editButtonItem,
            UIBarButtonItem(
                image: UIImage(systemName: "pencil"),
                style: .plain,
                target: self,
                action: #selector(renameTapped)
            )
        ]
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: slideReuseId)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: prefReuseId)
        tableView.rowHeight = UITableView.automaticDimension

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reload),
            name: SlideshowStore.didChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(thumbnailDidChange(_:)),
            name: TVLibraryStore.thumbnailDidChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        pinSlideThumbnails()
        tableView.reloadData()
    }

    @objc private func reload() {
        title = slideshow?.name ?? "Slideshow"
        pinSlideThumbnails()
        tableView.reloadData()
        if slideshow == nil {
            navigationController?.popViewController(animated: true)
        }
    }

    /// Batch import can purge `NSCache` before this screen paints; reload when a
    /// slide's thumb lands from disk / LocalMedia.
    @objc private func thumbnailDidChange(_ note: Notification) {
        guard let id = note.userInfo?[TVLibraryStore.thumbnailIdKey] as? String,
              let row = slides.firstIndex(where: { $0.id == id }) else { return }
        pinSlideThumbnails()
        let path = IndexPath(row: row, section: Section.slides.rawValue)
        guard tableView.numberOfSections > path.section,
              tableView.numberOfRows(inSection: path.section) > row else {
            tableView.reloadData()
            return
        }
        tableView.reloadRows(at: [path], with: .none)
    }

    /// Keeps slide previews pinned while this editor is on screen.
    private func pinSlideThumbnails() {
        TVLibraryStore.shared.setVisibleThumbnailIds(Set(slides.map(\.id)))
    }

    @objc private func renameTapped() {
        guard let slideshow else { return }
        let alert = UIAlertController(
            title: "Rename Slideshow", message: nil, preferredStyle: .alert
        )
        alert.addTextField { field in
            field.text = slideshow.name
            field.autocapitalizationType = .words
            UserDisplayName.configureTextField(field)
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            let name = alert.textFields?.first?.text ?? ""
            do {
                try SlideshowStore.shared.rename(id: slideshow.id, to: name)
            } catch {
                // An empty name used to fail silently, leaving the user believing the
                // rename had taken effect.
                self?.presentRenameFailure(error)
            }
        })
        present(alert, animated: true)
    }

    private func presentRenameFailure(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription
            ?? "That name couldn't be used."
        let alert = UIAlertController(
            title: "Couldn't Rename", message: message, preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    // MARK: - Table

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .preferences:
            guard let s = slideshow else { return 0 }
            // Autoplay, (Duration), (Loop), Crossfade, Live Ribbon
            return s.autoplay ? 5 : 3
        case .slides:
            return max(slides.count, 1)
        }
    }

    override func tableView(
        _ tableView: UITableView,
        titleForHeaderInSection section: Int
    ) -> String? {
        switch Section(rawValue: section)! {
        case .preferences: return "Preferences"
        case .slides: return "Images"
        }
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        switch Section(rawValue: indexPath.section)! {
        case .preferences:
            return preferenceCell(at: indexPath)
        case .slides:
            return slideCell(at: indexPath)
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard Section(rawValue: indexPath.section) == .preferences,
              let slideshow,
              slideshow.autoplay,
              preferenceKind(at: indexPath.row) == .duration else { return }
        presentDurationPicker(for: slideshow)
    }

    override func tableView(
        _ tableView: UITableView,
        canEditRowAt indexPath: IndexPath
    ) -> Bool {
        Section(rawValue: indexPath.section) == .slides && !slides.isEmpty
    }

    override func tableView(
        _ tableView: UITableView,
        canMoveRowAt indexPath: IndexPath
    ) -> Bool {
        Section(rawValue: indexPath.section) == .slides && !slides.isEmpty
    }

    override func tableView(
        _ tableView: UITableView,
        moveRowAt sourceIndexPath: IndexPath,
        to destinationIndexPath: IndexPath
    ) {
        guard slideshow != nil,
              Section(rawValue: sourceIndexPath.section) == .slides,
              Section(rawValue: destinationIndexPath.section) == .slides else { return }
        var ids = slides.map(\.id)
        let item = ids.remove(at: sourceIndexPath.row)
        ids.insert(item, at: destinationIndexPath.row)
        SlideshowStore.shared.reorder(itemIds: ids, inSlideshowId: slideshowId)
    }

    override func tableView(
        _ tableView: UITableView,
        targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath,
        toProposedIndexPath proposed: IndexPath
    ) -> IndexPath {
        guard Section(rawValue: proposed.section) == .slides else {
            return IndexPath(row: 0, section: Section.slides.rawValue)
        }
        return proposed
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard Section(rawValue: indexPath.section) == .slides, !slides.isEmpty else {
            return nil
        }
        let item = slides[indexPath.row]
        let remove = UIContextualAction(style: .destructive, title: "Remove") { _, _, done in
            SlideshowStore.shared.remove(itemId: item.id, fromSlideshowId: self.slideshowId)
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [remove])
    }

    // MARK: - Preference rows

    private enum PrefKind {
        case autoplay, duration, loop, crossfade, liveRibbon
    }

    private func preferenceKind(at row: Int) -> PrefKind {
        guard let s = slideshow, s.autoplay else {
            switch row {
            case 0: return .autoplay
            case 1: return .crossfade
            default: return .liveRibbon
            }
        }
        switch row {
        case 0: return .autoplay
        case 1: return .duration
        case 2: return .loop
        case 3: return .crossfade
        default: return .liveRibbon
        }
    }

    private func preferenceCell(at indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: prefReuseId, for: indexPath)
        cell.accessoryView = nil
        cell.accessoryType = .none
        cell.selectionStyle = .none
        var config = cell.defaultContentConfiguration()
        guard let slideshow else { return cell }

        switch preferenceKind(at: indexPath.row) {
        case .autoplay:
            config.text = "Autoplay"
            cell.contentConfiguration = config
            cell.accessoryView = makeSwitch(
                isOn: slideshow.autoplay,
                action: #selector(autoplayChanged(_:))
            )
        case .duration:
            config.text = "Duration"
            config.secondaryText = slideshow.autoplaySeconds.label
            cell.contentConfiguration = config
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
        case .loop:
            config.text = "Loop"
            cell.contentConfiguration = config
            cell.accessoryView = makeSwitch(
                isOn: slideshow.loop,
                action: #selector(loopChanged(_:))
            )
        case .crossfade:
            config.text = "Crossfade"
            cell.contentConfiguration = config
            cell.accessoryView = makeSwitch(
                isOn: slideshow.crossfade,
                action: #selector(crossfadeChanged(_:))
            )
        case .liveRibbon:
            config.text = "Show Ribbon When Live"
            config.secondaryText = "Thumbnails to jump between slides"
            cell.contentConfiguration = config
            cell.accessoryView = makeSwitch(
                isOn: slideshow.showRibbonWhenLive,
                action: #selector(liveRibbonChanged(_:))
            )
        }
        return cell
    }

    private func slideCell(at indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: slideReuseId, for: indexPath)
        var config = cell.defaultContentConfiguration()
        if slides.isEmpty {
            config.text = "No images"
            config.secondaryText = "Delete this Slideshow or create a new one."
            config.textProperties.color = .secondaryLabel
            cell.selectionStyle = .none
            cell.accessoryType = .none
        } else {
            let item = slides[indexPath.row]
            config.text = "Image \(indexPath.row + 1)"
            config.image = TVLibraryStore.shared.thumbnail(for: item.id)
            config.imageProperties.maximumSize = CGSize(width: 44, height: 44)
            config.imageProperties.cornerRadius = 6
            cell.selectionStyle = .none
        }
        cell.contentConfiguration = config
        return cell
    }

    private func makeSwitch(isOn: Bool, action: Selector) -> UISwitch {
        let toggle = UISwitch()
        toggle.isOn = isOn
        toggle.addTarget(self, action: action, for: .valueChanged)
        return toggle
    }

    private func presentDurationPicker(for slideshow: Slideshow) {
        let sheet = UIAlertController(
            title: "Duration", message: nil, preferredStyle: .actionSheet
        )
        for value in SlideshowAutoplaySeconds.allCases {
            let title = value == slideshow.autoplaySeconds
                ? "\(value.label) ✓"
                : value.label
            sheet.addAction(UIAlertAction(title: title, style: .default) { _ in
                SlideshowStore.shared.updatePreferences(
                    id: slideshow.id, autoplaySeconds: value
                )
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = tableView
            popover.sourceRect = tableView.rectForRow(
                at: IndexPath(row: 1, section: Section.preferences.rawValue)
            )
        }
        present(sheet, animated: true)
    }

    @objc private func autoplayChanged(_ sender: UISwitch) {
        SlideshowStore.shared.updatePreferences(id: slideshowId, autoplay: sender.isOn)
    }

    @objc private func loopChanged(_ sender: UISwitch) {
        SlideshowStore.shared.updatePreferences(id: slideshowId, loop: sender.isOn)
    }

    @objc private func crossfadeChanged(_ sender: UISwitch) {
        SlideshowStore.shared.updatePreferences(id: slideshowId, crossfade: sender.isOn)
    }

    @objc private func liveRibbonChanged(_ sender: UISwitch) {
        SlideshowStore.shared.updatePreferences(
            id: slideshowId, showRibbonWhenLive: sender.isOn
        )
    }
}
