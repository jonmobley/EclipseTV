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
        view.layer.cornerRadius = 8
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
        label.text = "Play Next"
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let playNextSwitch: UISwitch = {
        let control = UISwitch()
        control.accessibilityLabel = "Play Next"
        control.accessibilityHint =
            "When off, playback stops at the end of the current song"
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
        tableView.rowHeight = 56
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
            artworkView.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.45)
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
        tableView.reloadData()
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

extension AudioNowPlayingViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        AudioPlayerController.shared.queue.count
    }

    func tableView(
        _ tableView: UITableView,
        titleForHeaderInSection section: Int
    ) -> String? {
        let count = AudioPlayerController.shared.queue.count
        return count > 1 ? "Up Next · \(count) tracks" : "Now Playing"
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellReuseId, for: indexPath)
        var config = cell.defaultContentConfiguration()
        let player = AudioPlayerController.shared
        let trackId = player.queue[indexPath.row]
        let track = AudioStore.shared.track(id: trackId)
        config.text = track?.title ?? "Missing Track"
        config.secondaryText = track?.subtitle
        config.image = UIImage(systemName: "music.note")
        config.imageProperties.tintColor = .secondaryLabel
        let isCurrent = indexPath.row == player.currentIndex
        config.textProperties.font = .systemFont(
            ofSize: 16, weight: isCurrent ? .semibold : .regular
        )
        config.textProperties.color = isCurrent ? .systemBlue : .label
        cell.contentConfiguration = config
        cell.accessoryType = isCurrent ? .checkmark : .none
        cell.selectionStyle = .default
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        AudioPlayerController.shared.play(at: indexPath.row)
    }
}
