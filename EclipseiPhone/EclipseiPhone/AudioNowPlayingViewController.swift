//
//  AudioNowPlayingViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Compact Now Playing sheet: transport on top, queue list for quick track changes.
/// Landscape uses a mini-player-width card; the queue scrolls with the chrome.
final class AudioNowPlayingViewController: UIViewController {

    var onOpenLibrary: (() -> Void)?

    private let artworkView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.layer.cornerRadius = CornerRadii.compact
        view.backgroundColor = .tertiarySystemFill
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .headline)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let scrubber: UISlider = {
        let slider = UISlider()
        slider.accessibilityLabel = "Playback position"
        slider.translatesAutoresizingMaskIntoConstraints = false
        return slider
    }()

    private let elapsedLabel: UILabel = {
        let label = UILabel()
        label.font = AudioNowPlayingViewController.monospacedCaption()
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let remainingLabel: UILabel = {
        let label = UILabel()
        label.font = AudioNowPlayingViewController.monospacedCaption()
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.textAlignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let playNextLabel: UILabel = {
        let label = UILabel()
        label.text = "Autoplay Next"
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let playNextSwitch: UISwitch = {
        let control = UISwitch()
        control.accessibilityLabel = "Autoplay Next"
        control.accessibilityHint =
            "When off, playback stops at the end of the current song unless songs are in Up Next"
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()

    private let headerView = UIView()

    /// Caption-sized monospaced digits that still scale with Dynamic Type.
    private static func monospacedCaption() -> UIFont {
        let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .caption1)
        let base = UIFont.monospacedDigitSystemFont(
            ofSize: descriptor.pointSize, weight: .regular
        )
        return UIFontMetrics(forTextStyle: .caption1).scaledFont(for: base)
    }

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let playButton = UIButton(type: .system)
    private let prevButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private var isScrubbing = false
    private var observer: NSObjectProtocol?
    private let cellReuseId = "queueCell"
    private let upNextHeaderId = "upNextHeader"
    /// Last queue drawn; the list reloads only when this changes (not on progress ticks).
    private var lastQueueState: AudioPlayerController.QueueState?
    /// Set while a drag reorder hands its result to the player, so the post it causes
    /// doesn't reload rows the table has already moved.
    private var isApplyingLocalMove = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "Now Playing"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close, target: self, action: #selector(closeTapped)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Music", style: .plain, target: self, action: #selector(libraryTapped)
        )

        configureButtons()
        configurePlayNext()
        configureTable()
        layout()
        sizeTableHeaderToFit()
        scrubber.addTarget(self, action: #selector(scrubBegan), for: .touchDown)
        scrubber.addTarget(
            self, action: #selector(scrubEnded), for: [.touchUpInside, .touchUpOutside]
        )
        scrubber.addTarget(self, action: #selector(scrubChanged), for: .valueChanged)

        observer = NotificationCenter.default.addObserver(
            forName: AudioPlayerController.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reload()
        }
        reload()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        sizeTableHeaderToFit()
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    // MARK: - Private

    private func configureButtons() {
        let large = UIImage.SymbolConfiguration(pointSize: 26, weight: .semibold)
        let mid = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        playButton.setImage(
            UIImage(systemName: "play.fill", withConfiguration: large), for: .normal
        )
        prevButton.setImage(
            UIImage(systemName: "backward.fill", withConfiguration: mid), for: .normal
        )
        nextButton.setImage(
            UIImage(systemName: "forward.fill", withConfiguration: mid), for: .normal
        )
        for button in [playButton, prevButton, nextButton] {
            button.translatesAutoresizingMaskIntoConstraints = false
            button.tintColor = .label
        }
        playButton.accessibilityLabel = "Play"
        prevButton.accessibilityLabel = "Previous track"
        nextButton.accessibilityLabel = "Next track"
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
        prevButton.addTarget(self, action: #selector(prevTapped), for: .touchUpInside)
        nextButton.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)
    }

    private func configurePlayNext() {
        playNextSwitch.addTarget(
            self, action: #selector(playNextChanged(_:)), for: .valueChanged
        )
        playNextSwitch.isOn = AudioPlayerController.shared.playsNext
    }

    private func configureTable() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: cellReuseId)
        tableView.register(
            UpNextHeaderView.self, forHeaderFooterViewReuseIdentifier: upNextHeaderId
        )
        // Up Next rows reorder by press-and-drag (no edit mode, so taps still play).
        tableView.dragInteractionEnabled = true
        tableView.dragDelegate = self
        tableView.dropDelegate = self
        // At least 56pt, taller when a row has an artist line (a fixed 56 clipped it).
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 56
        tableView.tableFooterView = UIView()
        tableView.keyboardDismissMode = .onDrag
        tableView.alwaysBounceVertical = true
        tableView.sectionHeaderTopPadding = 8
    }

    private func layout() {
        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let transport = UIStackView(arrangedSubviews: [prevButton, playButton, nextButton])
        transport.axis = .horizontal
        transport.alignment = .center
        transport.distribution = .equalCentering
        transport.translatesAutoresizingMaskIntoConstraints = false

        let playNextRow = UIStackView(arrangedSubviews: [playNextLabel, playNextSwitch])
        playNextRow.axis = .horizontal
        playNextRow.alignment = .center
        playNextRow.translatesAutoresizingMaskIntoConstraints = false

        headerView.addSubview(artworkView)
        headerView.addSubview(textStack)
        headerView.addSubview(scrubber)
        headerView.addSubview(elapsedLabel)
        headerView.addSubview(remainingLabel)
        headerView.addSubview(transport)
        headerView.addSubview(playNextRow)

        NSLayoutConstraint.activate([
            artworkView.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 12),
            artworkView.leadingAnchor.constraint(
                equalTo: headerView.leadingAnchor, constant: 20
            ),
            artworkView.widthAnchor.constraint(equalToConstant: 56),
            artworkView.heightAnchor.constraint(equalToConstant: 56),

            textStack.leadingAnchor.constraint(
                equalTo: artworkView.trailingAnchor, constant: 12
            ),
            textStack.trailingAnchor.constraint(
                equalTo: headerView.trailingAnchor, constant: -20
            ),
            textStack.centerYAnchor.constraint(equalTo: artworkView.centerYAnchor),

            scrubber.topAnchor.constraint(equalTo: artworkView.bottomAnchor, constant: 14),
            scrubber.leadingAnchor.constraint(
                equalTo: headerView.leadingAnchor, constant: 20
            ),
            scrubber.trailingAnchor.constraint(
                equalTo: headerView.trailingAnchor, constant: -20
            ),

            elapsedLabel.topAnchor.constraint(equalTo: scrubber.bottomAnchor, constant: 2),
            elapsedLabel.leadingAnchor.constraint(equalTo: scrubber.leadingAnchor),

            remainingLabel.centerYAnchor.constraint(equalTo: elapsedLabel.centerYAnchor),
            remainingLabel.trailingAnchor.constraint(equalTo: scrubber.trailingAnchor),

            transport.topAnchor.constraint(equalTo: elapsedLabel.bottomAnchor, constant: 10),
            transport.leadingAnchor.constraint(
                equalTo: headerView.leadingAnchor, constant: 48
            ),
            transport.trailingAnchor.constraint(
                equalTo: headerView.trailingAnchor, constant: -48
            ),
            transport.heightAnchor.constraint(equalToConstant: 40),

            playNextRow.topAnchor.constraint(equalTo: transport.bottomAnchor, constant: 16),
            playNextRow.leadingAnchor.constraint(
                equalTo: headerView.leadingAnchor, constant: 20
            ),
            playNextRow.trailingAnchor.constraint(
                equalTo: headerView.trailingAnchor, constant: -20
            ),
            playNextRow.bottomAnchor.constraint(
                equalTo: headerView.bottomAnchor, constant: -8
            )
        ])

        tableView.tableHeaderView = headerView
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    /// Sizes the transport header so the queue table can scroll in short sheets.
    private func sizeTableHeaderToFit() {
        let width = tableView.bounds.width
        guard width > 1 else { return }
        headerView.frame.size.width = width
        headerView.setNeedsLayout()
        headerView.layoutIfNeeded()
        let height = headerView.systemLayoutSizeFitting(
            CGSize(width: width, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        let size = CGSize(width: width, height: height)
        guard abs(headerView.frame.height - size.height) > 0.5
            || abs(headerView.frame.width - size.width) > 0.5 else { return }
        headerView.frame.size = size
        tableView.tableHeaderView = headerView
    }

    private func reload() {
        let player = AudioPlayerController.shared
        guard let track = player.currentTrack else {
            dismiss(animated: true)
            return
        }
        titleLabel.text = track.title
        if let playlist = player.playlistName, !playlist.isEmpty {
            let artist = track.subtitle
            subtitleLabel.text = artist.isEmpty ? playlist : "\(artist) · \(playlist)"
        } else {
            subtitleLabel.text = track.subtitle.isEmpty ? " " : track.subtitle
        }
        if let art = player.artworkCache {
            artworkView.image = art
            artworkView.contentMode = .scaleAspectFill
            artworkView.tintColor = .secondaryLabel
            artworkView.backgroundColor = .tertiarySystemFill
        } else {
            artworkView.image = UIImage(systemName: "music.note")
            artworkView.contentMode = .center
            artworkView.tintColor = .white
            artworkView.backgroundColor = UIColor.accent.withAlphaComponent(0.45)
        }

        let duration = max(player.duration, 0.1)
        if !isScrubbing {
            scrubber.minimumValue = 0
            scrubber.maximumValue = Float(duration)
            scrubber.value = Float(player.currentTime)
        }
        elapsedLabel.text = format(player.currentTime)
        remainingLabel.text = "-" + format(max(0, duration - player.currentTime))

        let symbol = player.isPlaying ? "pause.fill" : "play.fill"
        let large = UIImage.SymbolConfiguration(pointSize: 26, weight: .semibold)
        playButton.setImage(UIImage(systemName: symbol, withConfiguration: large), for: .normal)
        playButton.accessibilityLabel = player.isPlaying ? "Pause" : "Play"
        playNextSwitch.isOn = player.playsNext
        let queueState = player.queueState
        if isApplyingLocalMove {
            lastQueueState = queueState
        } else if queueState != lastQueueState {
            lastQueueState = queueState
            tableView.reloadData()
        }
    }

    private func format(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    @objc private func closeTapped() { dismiss(animated: true) }
    @objc private func libraryTapped() {
        dismiss(animated: true) { [weak self] in
            self?.onOpenLibrary?()
        }
    }
    @objc private func playTapped() { AudioPlayerController.shared.togglePlayPause() }
    @objc private func prevTapped() { AudioPlayerController.shared.playPrevious() }
    @objc private func nextTapped() { AudioPlayerController.shared.playNext() }
    @objc private func playNextChanged(_ sender: UISwitch) {
        AudioPlayerController.shared.setPlaysNext(sender.isOn)
    }
    @objc private func scrubBegan() { isScrubbing = true }
    @objc private func scrubChanged() {
        elapsedLabel.text = format(TimeInterval(scrubber.value))
    }
    @objc private func scrubEnded() {
        isScrubbing = false
        AudioPlayerController.shared.seek(to: TimeInterval(scrubber.value))
    }
}

// MARK: - Queue Table

/// Sections of the Now Playing list: songs lined up with Play Next / Add to Queue
/// (only when there are some), then the playlist or Music list being played through.
private enum NowPlayingSection {
    case upNext
    case playlist
}

extension AudioNowPlayingViewController: UITableViewDataSource, UITableViewDelegate {

    private var sections: [NowPlayingSection] {
        AudioPlayerController.shared.upNext.isEmpty ? [.playlist] : [.upNext, .playlist]
    }

    private func section(at index: Int) -> NowPlayingSection {
        let all = sections
        return all.indices.contains(index) ? all[index] : .playlist
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let player = AudioPlayerController.shared
        switch self.section(at: section) {
        case .upNext: return player.upNext.count
        case .playlist: return player.queue.count
        }
    }

    /// Title of the playlist section: where the songs come from, and how many.
    static func playlistSectionTitle(
        playlistName: String?,
        trackCount: Int,
        hasUpNext: Bool
    ) -> String {
        let source = (playlistName?.isEmpty == false) ? playlistName! : "Music"
        guard trackCount > 1 else { return hasUpNext ? "Then \(source)" : "Now Playing" }
        let prefix = hasUpNext ? "Then " : ""
        return "\(prefix)\(source) · \(trackCount) tracks"
    }

    func tableView(
        _ tableView: UITableView,
        titleForHeaderInSection section: Int
    ) -> String? {
        guard self.section(at: section) == .playlist else { return nil }
        let player = AudioPlayerController.shared
        return Self.playlistSectionTitle(
            playlistName: player.playlistName,
            trackCount: player.queue.count,
            hasUpNext: !player.upNext.isEmpty
        )
    }

    func tableView(
        _ tableView: UITableView,
        viewForHeaderInSection section: Int
    ) -> UIView? {
        guard self.section(at: section) == .upNext,
              let header = tableView.dequeueReusableHeaderFooterView(
                withIdentifier: upNextHeaderId
              ) as? UpNextHeaderView
        else { return nil }
        header.configure(count: AudioPlayerController.shared.upNext.count)
        return header
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellReuseId, for: indexPath)
        var config = cell.defaultContentConfiguration()
        let player = AudioPlayerController.shared
        let isUpNext = section(at: indexPath.section) == .upNext
        let ids = isUpNext ? player.upNext.trackIds : player.queue
        guard ids.indices.contains(indexPath.row) else { return cell }
        let track = AudioStore.shared.track(id: ids[indexPath.row])
        config.text = track?.title ?? "Missing Track"
        let subtitle = track?.subtitle ?? ""
        config.secondaryText = subtitle.isEmpty ? nil : subtitle
        // Keep one-line rows at the old 56pt; rows with an artist grow to fit it.
        if subtitle.isEmpty {
            config.directionalLayoutMargins.top = 16
            config.directionalLayoutMargins.bottom = 16
        }
        config.image = UIImage(systemName: "music.note")
        config.imageProperties.tintColor = .secondaryLabel
        // The playlist row is "current" only while it, not an Up Next song, is playing.
        let isCurrent = !isUpNext
            && !player.isPlayingFromUpNext
            && indexPath.row == player.currentIndex
        config.textProperties.font = .systemFont(
            ofSize: 16, weight: isCurrent ? .semibold : .regular
        )
        config.textProperties.color = isCurrent ? .accent : .label
        cell.contentConfiguration = config
        cell.accessoryType = isCurrent ? .checkmark : .none
        cell.selectionStyle = .default
        cell.accessibilityCustomActions = isUpNext
            ? upNextAccessibilityActions(row: indexPath.row, count: ids.count)
            : nil
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let player = AudioPlayerController.shared
        switch section(at: indexPath.section) {
        case .upNext:
            player.playUpNext(at: indexPath.row)
        case .playlist:
            guard player.queue.indices.contains(indexPath.row) else { return }
            let id = player.queue[indexPath.row]
            if !player.isPlayingFromUpNext, player.tapStopsPlayback(for: id) {
                player.stop()
            } else {
                player.play(at: indexPath.row)
            }
        }
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let player = AudioPlayerController.shared
        switch section(at: indexPath.section) {
        case .upNext:
            guard player.upNext.trackIds.indices.contains(indexPath.row) else { return nil }
            let id = player.upNext.trackIds[indexPath.row]
            let remove = UIContextualAction(style: .destructive, title: "Remove") { _, _, done in
                AudioPlayerController.shared.removeFromUpNext(id)
                done(true)
            }
            return UISwipeActionsConfiguration(actions: [remove])
        case .playlist:
            return nil
        }
    }

    func tableView(
        _ tableView: UITableView,
        leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let player = AudioPlayerController.shared
        guard section(at: indexPath.section) == .playlist,
              player.queue.indices.contains(indexPath.row)
        else { return nil }
        return AudioQueueActions.leadingSwipe(for: player.queue[indexPath.row], host: self)
    }

    // MARK: Reorder (Up Next only)

    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        section(at: indexPath.section) == .upNext
    }

    func tableView(
        _ tableView: UITableView,
        targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath,
        toProposedIndexPath proposedIndexPath: IndexPath
    ) -> IndexPath {
        guard proposedIndexPath.section == sourceIndexPath.section else {
            // Dragged past the end of Up Next: keep it in Up Next, at the nearest end.
            let last = max(0, AudioPlayerController.shared.upNext.count - 1)
            let row = proposedIndexPath.section < sourceIndexPath.section ? 0 : last
            return IndexPath(row: row, section: sourceIndexPath.section)
        }
        return proposedIndexPath
    }

    func tableView(
        _ tableView: UITableView,
        moveRowAt sourceIndexPath: IndexPath,
        to destinationIndexPath: IndexPath
    ) {
        isApplyingLocalMove = true
        AudioPlayerController.shared.moveUpNext(
            from: sourceIndexPath.row, to: destinationIndexPath.row
        )
        isApplyingLocalMove = false
    }

    private func upNextAccessibilityActions(row: Int, count: Int) -> [UIAccessibilityCustomAction] {
        var actions: [UIAccessibilityCustomAction] = []
        if row > 0 {
            actions.append(UIAccessibilityCustomAction(name: "Move Up") { _ in
                AudioPlayerController.shared.moveUpNext(from: row, to: row - 1)
                return true
            })
        }
        if row < count - 1 {
            actions.append(UIAccessibilityCustomAction(name: "Move Down") { _ in
                AudioPlayerController.shared.moveUpNext(from: row, to: row + 1)
                return true
            })
        }
        actions.append(UIAccessibilityCustomAction(
            name: AudioQueueActions.removeFromUpNextTitle
        ) { _ in
            let ids = AudioPlayerController.shared.upNext.trackIds
            guard ids.indices.contains(row) else { return false }
            AudioPlayerController.shared.removeFromUpNext(ids[row])
            return true
        })
        return actions
    }
}

// MARK: - Drag to reorder Up Next

extension AudioNowPlayingViewController: UITableViewDragDelegate, UITableViewDropDelegate {

    func tableView(
        _ tableView: UITableView,
        itemsForBeginning session: UIDragSession,
        at indexPath: IndexPath
    ) -> [UIDragItem] {
        guard section(at: indexPath.section) == .upNext else { return [] }
        let item = UIDragItem(itemProvider: NSItemProvider())
        item.localObject = indexPath
        return [item]
    }

    func tableView(
        _ tableView: UITableView,
        dropSessionDidUpdate session: UIDropSession,
        withDestinationIndexPath destinationIndexPath: IndexPath?
    ) -> UITableViewDropProposal {
        guard session.localDragSession != nil else {
            return UITableViewDropProposal(operation: .forbidden)
        }
        return UITableViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
    }

    func tableView(
        _ tableView: UITableView,
        performDropWith coordinator: UITableViewDropCoordinator
    ) {
        // Local reorders go through `moveRowAt`.
    }
}

/// "Up Next" section header with a Clear button (same words as the Mac's Up Next).
private final class UpNextHeaderView: UITableViewHeaderFooterView {

    private let titleLabel = UILabel()
    private let clearButton = UIButton(type: .system)

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        // Own label, not a content configuration: a configuration's view sits over
        // added subviews and hid the Clear button.
        let style = UIListContentConfiguration.plainHeader().textProperties
        titleLabel.font = style.font
        titleLabel.textColor = style.color
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)
        clearButton.setTitle("Clear", for: .normal)
        clearButton.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
        clearButton.titleLabel?.adjustsFontForContentSizeCategory = true
        clearButton.accessibilityLabel = "Clear Up Next"
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.addAction(UIAction { _ in
            AudioPlayerController.shared.clearUpNext()
        }, for: .touchUpInside)
        contentView.addSubview(clearButton)
        let margins = contentView.layoutMarginsGuide
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            titleLabel.topAnchor.constraint(equalTo: margins.topAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: margins.bottomAnchor),
            titleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: clearButton.leadingAnchor, constant: -8
            ),
            clearButton.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            clearButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(count: Int) {
        titleLabel.text = count > 1 ? "Up Next · \(count) tracks" : "Up Next"
    }
}
