//
//  GettingStartedViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// In-app overview guide aligned to the five cores: Shows, AirPlay, Camera, Music, EclipseTV.
final class GettingStartedViewController: UITableViewController {

    private struct Topic {
        let title: String
        let body: String
        let systemImage: String
        let tint: UIColor
    }

    private let topics: [Topic] = [
        Topic(
            title: "Welcome",
            body: """
            Eclipse is your presentation remote: build Shows, present with AirPlay, \
            optionally use Camera and ambient Music, and link EclipseTV only when you \
            want media sync with the TV app.
            """,
            systemImage: "sparkles",
            tint: .systemBlue
        ),
        Topic(
            title: "Shows",
            body: """
            A Show is a set of media you present together. Tap New Show, name it, and \
            open it to add images, videos, websites, or a slideshow. Your recent Shows \
            appear on Home — tap one to jump back in.
            """,
            systemImage: "rectangle.stack.fill",
            tint: .systemIndigo
        ),
        Topic(
            title: "Presenting",
            body: """
            Start AirPlay from Control Center — that’s enough to present. Tap any tile \
            in a Show to put it on screen; the live preview mirrors the audience. The \
            header AirPlay & EclipseTV control shows connection status — tap it for \
            Link EclipseTV… or How to AirPlay.
            """,
            systemImage: "airplayvideo",
            tint: .systemTeal
        ),
        Topic(
            title: "Camera",
            body: """
            Inside a Show, open Camera to put a live feed on AirPlay. Capture stills or \
            clips into your Show — those stay on your phones (and can sync with iCloud), \
            and are never sent to the EclipseTV app library.
            """,
            systemImage: "camera.fill",
            tint: .systemGreen
        ),
        Topic(
            title: "Music",
            body: """
            Swipe left from Home when you can, or choose Music in the Home menu. A music \
            circle appears while something is playing — tap to expand controls, hold to \
            stop. Ambient audio pauses when a video needs the speakers.
            """,
            systemImage: "music.note",
            tint: .systemPink
        ),
        Topic(
            title: "EclipseTV Link",
            body: """
            Linking EclipseTV (optional) syncs imported media with the Apple TV app and \
            enables multi-TV. AirPlay alone is enough for Shows. Use the header status \
            control or Settings → EclipseTV to link with a pairing code.
            """,
            systemImage: "tv",
            tint: .systemCyan
        ),
        Topic(
            title: "Display Mode & Tools",
            body: """
            Landscape (16:9) is the default; Vertical is in Settings → Display Mode. \
            Inside a Show: Blackout blanks the display, Background sets a resting image, \
            Screensaver loops a video, and + adds media.
            """,
            systemImage: "moon.fill",
            tint: .systemPurple
        ),
        Topic(
            title: "Tips",
            body: """
            On Home, long-press a Show for rename, share, or delete. Inside a Show, \
            long-press a tile to arrange, or use ⋯ for Loop, Mute, Thumbnail, cover, \
            and remove. Getting Started stays in the Home menu anytime.
            """,
            systemImage: "lightbulb.fill",
            tint: .systemYellow
        )
    ]

    // MARK: - Lifecycle

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Getting Started"
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: self, action: #selector(doneTapped)
        )
        tableView.register(
            GettingStartedTopicCell.self,
            forCellReuseIdentifier: GettingStartedTopicCell.reuseIdentifier
        )
        tableView.allowsSelection = false
        tableView.separatorStyle = .none
        tableView.tableHeaderView = makeHeroHeader()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        resizeHeroHeader(toWidth: tableView.bounds.width)
    }

    /// Sizes the hero header to `width`, reporting whether it had to change anything.
    ///
    /// Assigning `tableHeaderView` schedules another layout pass, which calls back into
    /// here, so this has to report "settled" once the frame fits or the two spin
    /// forever. That is why the header stays frame-based (`translatesAutoresizing…` on):
    /// a self-sizing header rewrites the frame Auto Layout thinks it should have after
    /// each assignment, so the comparison never converges.
    @discardableResult
    func resizeHeroHeader(toWidth width: CGFloat) -> Bool {
        guard let header = tableView.tableHeaderView, width > 0 else { return false }
        let fitted = header.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        // Sub-point slack: rounding alone must not qualify as a change.
        guard abs(header.frame.width - width) > 0.5
            || abs(header.frame.height - fitted.height) > 0.5 else { return false }
        header.frame.size = CGSize(width: width, height: fitted.height)
        tableView.tableHeaderView = header
        return true
    }

    // MARK: - Table

    override func numberOfSections(in tableView: UITableView) -> Int {
        topics.count
    }

    override func tableView(
        _ tableView: UITableView, numberOfRowsInSection section: Int
    ) -> Int {
        1
    }

    override func tableView(
        _ tableView: UITableView, cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: GettingStartedTopicCell.reuseIdentifier,
            for: indexPath
        ) as? GettingStartedTopicCell else {
            return UITableViewCell()
        }
        let topic = topics[indexPath.section]
        cell.configure(
            title: topic.title,
            body: topic.body,
            systemImage: topic.systemImage,
            tint: topic.tint
        )
        return cell
    }

    // MARK: - Private

    /// Soft hero above the topic cards: glyph + short pitch.
    private func makeHeroHeader() -> UIView {
        // Frame-based on purpose — see `resizeHeroHeader(toWidth:)`.
        let container = UIView()

        let badge = UIView()
        badge.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.18)
        badge.layer.cornerRadius = 22
        badge.layer.cornerCurve = .continuous
        badge.translatesAutoresizingMaskIntoConstraints = false

        let glyph = UIImageView(
            image: UIImage(
                systemName: "lightbulb.max.fill",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 28, weight: .semibold)
            )
        )
        glyph.tintColor = .systemBlue
        glyph.contentMode = .scaleAspectFit
        glyph.translatesAutoresizingMaskIntoConstraints = false
        badge.addSubview(glyph)

        let title = UILabel()
        title.text = "Learn the ropes"
        title.font = .preferredFont(forTextStyle: .title2)
        title.adjustsFontForContentSizeCategory = true
        title.textColor = .label
        title.textAlignment = .center

        let subtitle = UILabel()
        subtitle.text = "Shows, AirPlay, Camera, Music, and optional EclipseTV — the tools you’ll use every night."
        subtitle.font = .preferredFont(forTextStyle: .subheadline)
        subtitle.adjustsFontForContentSizeCategory = true
        subtitle.textColor = .secondaryLabel
        subtitle.textAlignment = .center
        subtitle.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [badge, title, subtitle])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.setCustomSpacing(16, after: badge)
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: 64),
            badge.heightAnchor.constraint(equalToConstant: 64),
            glyph.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
            glyph.centerYAnchor.constraint(equalTo: badge.centerYAnchor),

            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -28),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
        ])
        return container
    }

    @objc private func doneTapped() {
        dismiss(animated: true)
    }
}
