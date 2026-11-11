//
//  SlideshowDetailViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Edits a slideshow: its name, playback preferences, and the ordered slides.
///
/// Built so a whole slideshow can be prepared before it goes live:
/// - The name is its own row, edited in place.
/// - Each slide shows its thumbnail, an editable name, and its own Fit / Fill.
/// - Slides reorder by dragging and remove by swiping, without an Edit mode.
final class SlideshowDetailViewController: UITableViewController,
    UITableViewDragDelegate, UITableViewDropDelegate, UITextFieldDelegate {

    private enum Section: Int, CaseIterable {
        case title
        case preferences
        case slides
    }

    /// Applies Fit / Fill to a slide the way the grid does (saves, syncs, tells the
    /// Apple TV, and reframes it if it is live). Set by the presenter.
    var onApplyScreenFit: ((MediaFitMode, LibraryItemDTO) -> Void)?

    private let slideshowId: UUID
    private let titleReuseId = "slideshowTitleCell"
    private let prefReuseId = "slideshowPrefCell"
    private let emptyReuseId = "slideshowEmptyCell"
    private let titleField = UITextField()

    private var slideshow: Slideshow? {
        SlideshowStore.shared.slideshow(id: slideshowId)
    }

    private var slides: [LibraryItemDTO] {
        guard let slideshow else { return [] }
        let store = TVLibraryStore.shared
        return slideshow.itemIds.compactMap { id in
            guard let item = store.item(id: id), !item.isVideo else { return nil }
            return item
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
        navigationItem.title = "Slideshow"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: titleReuseId)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: prefReuseId)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: emptyReuseId)
        tableView.register(SlideshowSlideCell.self, forCellReuseIdentifier: SlideshowSlideCell.reuseId)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.keyboardDismissMode = .interactive
        // Reorder by dragging a slide, no Edit mode needed.
        tableView.dragInteractionEnabled = true
        tableView.dragDelegate = self
        tableView.dropDelegate = self
        configureTitleField()

        let center = NotificationCenter.default
        center.addObserver(
            self, selector: #selector(reload),
            name: SlideshowStore.didChangeNotification, object: nil
        )
        center.addObserver(
            self, selector: #selector(thumbnailDidChange(_:)),
            name: TVLibraryStore.thumbnailDidChangeNotification, object: nil
        )
        center.addObserver(
            self, selector: #selector(reloadSlides),
            name: MediaTitleStore.didChangeNotification, object: nil
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
        guard slideshow != nil else {
            navigationController?.popViewController(animated: true)
            return
        }
        if !titleField.isFirstResponder {
            titleField.text = slideshow?.name
        }
        pinSlideThumbnails()
        // Don't reload under a name being typed: it would end the edit.
        guard !isEditingText else { return }
        tableView.reloadData()
    }

    @objc private func reloadSlides() {
        guard !isEditingText else { return }
        tableView.reloadSections(IndexSet(integer: Section.slides.rawValue), with: .none)
    }

    private var isEditingText: Bool {
        view.window != nil && tableView.findFirstResponder() != nil
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
        // Repaint only the thumbnail, so a name being typed in that row survives.
        if let cell = tableView.cellForRow(at: path) as? SlideshowSlideCell {
            configure(cell, for: slides[row], position: row + 1)
        }
    }

    /// Keeps slide previews pinned while this editor is on screen.
    private func pinSlideThumbnails() {
        TVLibraryStore.shared.setVisibleThumbnailIds(Set(slides.map(\.id)))
    }

    // MARK: - Title

    private func configureTitleField() {
        titleField.font = .preferredFont(forTextStyle: .title2).bold()
        titleField.adjustsFontForContentSizeCategory = true
        titleField.placeholder = "Slideshow name"
        titleField.text = slideshow?.name
        titleField.returnKeyType = .done
        titleField.autocapitalizationType = .words
        titleField.clearButtonMode = .whileEditing
        titleField.accessibilityLabel = "Slideshow name"
        titleField.delegate = self
        titleField.translatesAutoresizingMaskIntoConstraints = false
        UserDisplayName.configureTextField(titleField)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        guard textField === titleField, let slideshow else { return }
        let name = textField.text ?? ""
        guard name != slideshow.name else { return }
        do {
            try SlideshowStore.shared.rename(id: slideshow.id, to: name)
        } catch {
            // Put the old name back rather than leave an unsaved one on screen.
            textField.text = slideshow.name
            presentRenameFailure(error)
        }
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
        case .title:
            return 1
        case .preferences:
            guard let s = slideshow else { return 0 }
            // Autoplay, (Duration), (Loop), Crossfade
            return s.autoplay ? 4 : 2
        case .slides:
            return max(slides.count, 1)
        }
    }

    override func tableView(
        _ tableView: UITableView,
        titleForHeaderInSection section: Int
    ) -> String? {
        switch Section(rawValue: section)! {
        case .title: return nil
        case .preferences: return "Playback"
        case .slides:
            let count = slides.count
            return count == 1 ? "1 Slide" : "\(count) Slides"
        }
    }

    override func tableView(
        _ tableView: UITableView,
        titleForFooterInSection section: Int
    ) -> String? {
        guard Section(rawValue: section) == .slides, slides.count > 1 else { return nil }
        return "Drag to reorder. Swipe left to remove a slide from this slideshow."
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        switch Section(rawValue: indexPath.section)! {
        case .title:
            return titleCell(at: indexPath)
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
              preferenceKind(at: indexPath.row) == .duration else { return }
        presentDurationPicker(for: slideshow, from: indexPath)
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
        Section(rawValue: indexPath.section) == .slides && slides.count > 1
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
        guard ids.indices.contains(sourceIndexPath.row) else { return }
        let item = ids.remove(at: sourceIndexPath.row)
        ids.insert(item, at: min(destinationIndexPath.row, ids.count))
        SlideshowStore.shared.reorder(itemIds: ids, inSlideshowId: slideshowId)
    }

    override func tableView(
        _ tableView: UITableView,
        targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath,
        toProposedIndexPath proposed: IndexPath
    ) -> IndexPath {
        let slidesSection = Section.slides.rawValue
        if proposed.section < slidesSection {
            return IndexPath(row: 0, section: slidesSection)
        }
        return proposed
    }

    /// Edit-style minus → Remove (same unlink as the swipe action).
    override func tableView(
        _ tableView: UITableView,
        commit editingStyle: UITableViewCell.EditingStyle,
        forRowAt indexPath: IndexPath
    ) {
        guard editingStyle == .delete,
              Section(rawValue: indexPath.section) == .slides,
              slides.indices.contains(indexPath.row) else { return }
        SlideshowStore.shared.remove(
            itemId: slides[indexPath.row].id, fromSlideshowId: slideshowId
        )
    }

    override func tableView(
        _ tableView: UITableView,
        titleForDeleteConfirmationButtonForRowAt indexPath: IndexPath
    ) -> String? {
        "Remove"
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard Section(rawValue: indexPath.section) == .slides, !slides.isEmpty else {
            return nil
        }
        let item = slides[indexPath.row]
        // Remove only unlinks; the media stays in Library. Like removing a Show
        // member, the swipe is the confirmation.
        let remove = UIContextualAction(style: .destructive, title: "Remove") {
            [weak self] _, _, done in
            guard let self else {
                done(false)
                return
            }
            SlideshowStore.shared.remove(
                itemId: item.id, fromSlideshowId: self.slideshowId
            )
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [remove])
    }

    // MARK: - Drag to reorder

    func tableView(
        _ tableView: UITableView,
        itemsForBeginning session: UIDragSession,
        at indexPath: IndexPath
    ) -> [UIDragItem] {
        guard Section(rawValue: indexPath.section) == .slides,
              slides.count > 1,
              slides.indices.contains(indexPath.row) else { return [] }
        let item = UIDragItem(itemProvider: NSItemProvider())
        item.localObject = slides[indexPath.row].id
        return [item]
    }

    func tableView(
        _ tableView: UITableView,
        dropSessionDidUpdate session: UIDropSession,
        withDestinationIndexPath destinationIndexPath: IndexPath?
    ) -> UITableViewDropProposal {
        // Only slides moving within this list; the table calls `moveRowAt`.
        guard session.localDragSession != nil,
              let destinationIndexPath,
              Section(rawValue: destinationIndexPath.section) == .slides else {
            return UITableViewDropProposal(operation: .forbidden)
        }
        return UITableViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
    }

    func tableView(_ tableView: UITableView, performDropWith coordinator: UITableViewDropCoordinator) {
        // Local reorders are applied through `moveRowAt`.
    }

    // MARK: - Rows

    private func titleCell(at indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: titleReuseId, for: indexPath)
        cell.selectionStyle = .none
        if titleField.superview !== cell.contentView {
            titleField.removeFromSuperview()
            cell.contentView.addSubview(titleField)
            let margins = cell.contentView.layoutMarginsGuide
            NSLayoutConstraint.activate([
                titleField.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
                titleField.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
                titleField.topAnchor.constraint(equalTo: margins.topAnchor, constant: 4),
                titleField.bottomAnchor.constraint(equalTo: margins.bottomAnchor, constant: -4)
            ])
        }
        if !titleField.isFirstResponder {
            titleField.text = slideshow?.name
        }
        return cell
    }

    private func slideCell(at indexPath: IndexPath) -> UITableViewCell {
        guard !slides.isEmpty else {
            let cell = tableView.dequeueReusableCell(withIdentifier: emptyReuseId, for: indexPath)
            var config = cell.defaultContentConfiguration()
            config.text = "No slides"
            config.secondaryText = "Delete this Slideshow or create a new one."
            config.textProperties.color = .secondaryLabel
            cell.contentConfiguration = config
            cell.selectionStyle = .none
            return cell
        }
        let cell = tableView.dequeueReusableCell(
            withIdentifier: SlideshowSlideCell.reuseId, for: indexPath
        ) as! SlideshowSlideCell
        configure(cell, for: slides[indexPath.row], position: indexPath.row + 1)
        return cell
    }

    private func configure(_ cell: SlideshowSlideCell, for item: LibraryItemDTO, position: Int) {
        // Fit and Fill are the same picture on a slide already shaped like the screen,
        // so the control is hidden there. An unmeasured slide keeps it.
        let differs = MediaFitAvailability.fitDiffersFromFill(forId: item.id) ?? true
        cell.configure(
            thumbnail: TVLibraryStore.shared.thumbnail(for: item.id),
            name: MediaTitleStore.title(forId: item.id),
            position: position,
            fitMode: differs ? MediaFitSettings.mode(forId: item.id) : nil,
            hasCustomFraming: MediaFramingStore.hasFraming(forId: item.id)
        )
        cell.onRename = { text in
            MediaTitleStore.setTitle(text, forId: item.id)
        }
        cell.onSelectFit = { [weak self] mode in
            self?.onApplyScreenFit?(mode, item)
            self?.reloadSlides()
        }
    }

    // MARK: - Preferences

    private enum PrefKind {
        case autoplay, duration, loop, crossfade
    }

    private func preferenceKind(at row: Int) -> PrefKind {
        guard let s = slideshow, s.autoplay else {
            return row == 0 ? .autoplay : .crossfade
        }
        switch row {
        case 0: return .autoplay
        case 1: return .duration
        case 2: return .loop
        default: return .crossfade
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
        }
        return cell
    }

    private func makeSwitch(isOn: Bool, action: Selector) -> UISwitch {
        let toggle = UISwitch()
        toggle.isOn = isOn
        toggle.addTarget(self, action: action, for: .valueChanged)
        return toggle
    }

    private func presentDurationPicker(for slideshow: Slideshow, from indexPath: IndexPath) {
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
            popover.sourceRect = tableView.rectForRow(at: indexPath)
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
}

private extension UIView {
    /// The first responder in this view's subtree, if any.
    func findFirstResponder() -> UIView? {
        if isFirstResponder { return self }
        for subview in subviews {
            if let responder = subview.findFirstResponder() { return responder }
        }
        return nil
    }
}

private extension UIFont {
    /// This font at bold weight, keeping its size and Dynamic Type style.
    func bold() -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(.traitBold) else { return self }
        return UIFont(descriptor: descriptor, size: 0)
    }
}
