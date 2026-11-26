//
//  CameraLiveViewController+LiveOutput.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Live Output Thumbnail (what's on AirPlay while previewing)

extension CameraLiveViewController {

    /// Adds the program thumb (called from `viewDidLoad`).
    func setupLiveOutputThumb() {
        view.addSubview(liveOutputThumbView)
    }

    /// The "what's live" card shows while AirPlay is connected (including camera
    /// live), and also with no TV when something is live on the phone itself
    /// (Practice Mode, or an Apple TV link): whatever was live when the camera
    /// opened is the first card, not a gap.
    static func showsLiveOutputThumb(isConnected: Bool, hasLiveSource: Bool = false) -> Bool {
        isConnected || hasLiveSource
    }

    /// What the audience sees right now: the AirPlay picture, else the camera once
    /// it is live, else the card that is live in the Show.
    var liveOutputSource: PresentationSource? {
        let mgr = ExternalDisplayManager.shared
        if let presented = mgr.presentedSource { return presented }
        if mgr.isCameraModeActive { return .camera }
        // The Show screen stops answering once this screen covers it, so fall back
        // to what it said was live as the camera opened.
        return mgr.currentSourceProvider?() ?? entryLiveSource
    }

    /// Whether the "what's live" card has anything to show.
    var showsLiveOutputCard: Bool {
        Self.showsLiveOutputThumb(
            isConnected: ExternalDisplayManager.shared.isConnected,
            hasLiveSource: liveOutputSource != nil
        )
    }

    /// Places the program thumb at the bottom-leading corner of the panel.
    func layoutLiveOutputThumb(panel: CGRect) {
        let shouldShow = showsLiveOutputCard
        liveOutputThumbView.isHidden = !shouldShow
        guard shouldShow else { return }

        let short = Self.alternateStillThumbShortSide
        let aspect = ExternalOutputSettings.outputAspectRatio
        let width = aspect >= 1 ? short * aspect : short
        let height = width / aspect
        let inset = cameraThumbEdgeInset(panel: panel)
        liveOutputThumbView.frame = CGRect(
            x: panel.minX + inset,
            y: panel.maxY - inset - height,
            width: width,
            height: height
        )
        refreshLiveOutputAppearance()
        view.bringSubviewToFront(liveOutputThumbView)
    }

    /// Loads art for the current AirPlay source into the in-panel program thumb.
    func refreshLiveOutputAppearance() {
        configureLiveOutputThumb(liveOutputThumbView)
    }

    /// Loads art for the current AirPlay source into any program thumb
    /// (the in-panel monitor or a stacked-grid tile).
    func configureLiveOutputThumb(_ thumb: CameraLiveOutputThumbView) {
        guard let source = liveOutputSource else {
            thumb.configure(image: nil, symbol: nil, fill: .black)
            return
        }
        let art = liveOutputArt(for: source)
        thumb.configure(
            image: art.image,
            symbol: art.symbol,
            fill: art.fill,
            title: art.title
        )
    }

    // MARK: - Art

    private struct LiveOutputArt {
        let image: UIImage?
        let symbol: String
        let fill: UIColor
        let title: String
    }

    /// Still / icon for a presentation source, preferring cached library thumbs.
    private func liveOutputArt(for source: PresentationSource) -> LiveOutputArt {
        let dim = UIColor.mediaPlaceholder
        switch source.content {
        case .camera:
            return LiveOutputArt(
                image: CameraManager.shared.latestSampleImage
                    ?? CameraManager.shared.lastFrame,
                symbol: "camera.fill",
                fill: dim,
                title: "Camera"
            )
        case .ptzCamera:
            return LiveOutputArt(image: nil, symbol: "web.camera", fill: dim, title: "PTZ Camera")
        case .black:
            return LiveOutputArt(
                image: nil, symbol: "moon.fill", fill: .black, title: "Blackout"
            )
        case .prompter:
            return LiveOutputArt(image: nil, symbol: ThumbnailTypeIcon.prompter.systemName, fill: dim, title: "Prompter")
        case .countdown:
            return LiveOutputArt(
                image: nil,
                symbol: "timer",
                fill: dim,
                title: CountdownController.shared.displayString
            )
        case .unavailable(let thumb, _):
            return LiveOutputArt(
                image: thumb, symbol: "photo", fill: dim, title: "Unavailable"
            )
        case .screensaver:
            return LiveOutputArt(
                image: ScreensaverStore.poster,
                symbol: "sparkles.tv",
                fill: dim,
                title: "Screensaver"
            )
        case .web:
            let id = ExternalDisplayManager.shared.liveWebPageId
            let page = id.flatMap { WebPageStore.shared.page(id: $0) }
            return LiveOutputArt(
                image: id.flatMap { WebThumbnailStore.shared.image(for: $0) },
                symbol: ThumbnailTypeIcon.website.systemName,
                fill: dim,
                title: page?.title ?? "Website"
            )
        case .webVideo:
            let id = ExternalDisplayManager.shared.liveWebVideoPageId
            let page = id.flatMap { WebPageStore.shared.page(id: $0) }
            return LiveOutputArt(
                image: id.flatMap { WebThumbnailStore.shared.image(for: $0) },
                symbol: "play.rectangle.fill",
                fill: dim,
                title: page?.title ?? "Video"
            )
        case .pdf:
            let id = ExternalDisplayManager.shared.livePDFDocumentId
            let doc = PDFStore.shared.documents.first { $0.id == id }
            return LiveOutputArt(
                image: id.flatMap { PDFThumbnailStore.shared.image(for: $0) },
                symbol: ThumbnailTypeIcon.pdf.systemName,
                fill: dim,
                title: doc?.title ?? "PDF"
            )
        case .image(let url, _, _):
            return LiveOutputArt(
                image: stillFromPresentationURL(url),
                symbol: "photo",
                fill: dim,
                title: imageOutputTitle(for: url)
            )
        case .video(let url, _, _):
            return LiveOutputArt(
                image: stillFromPresentationURL(url),
                symbol: "film",
                fill: dim,
                title: "Video"
            )
        }
    }

    /// Library thumb, in-memory Background / Screensaver, or a downscaled file still.
    private func stillFromPresentationURL(_ url: URL) -> UIImage? {
        let id = url.deletingPathExtension().lastPathComponent
        if let thumb = TVLibraryStore.shared.thumbnail(for: id) {
            return thumb
        }
        if let logoURL = LogoStore.shared.fileURL,
           url.standardizedFileURL == logoURL.standardizedFileURL {
            return LogoStore.shared.image
        }
        if let ss = ScreensaverStore.presentationSource,
           case .image(let ssURL, _, _) = ss.content,
           url.standardizedFileURL == ssURL.standardizedFileURL {
            return ScreensaverStore.poster
        }
        guard url.isFileURL,
              let image = UIImage(contentsOfFile: url.path) else { return nil }
        let side = Self.alternateStillThumbShortSide * 3
        return image.preparingThumbnail(of: CGSize(width: side, height: side))
            ?? image
    }

    /// Distinguishes Background from a library still when the URL is a logo file.
    private func imageOutputTitle(for url: URL) -> String {
        if let logoURL = LogoStore.shared.fileURL,
           url.standardizedFileURL == logoURL.standardizedFileURL {
            return "Background"
        }
        if let ss = ScreensaverStore.presentationSource,
           case .image(let ssURL, _, _) = ss.content,
           url.standardizedFileURL == ssURL.standardizedFileURL {
            return "Screensaver"
        }
        return "Photo"
    }
}

// MARK: - Thumb View

/// Compact program monitor: still or symbol, plus a LIVE caption.
final class CameraLiveOutputThumbView: UIView {

    private let imageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let symbolView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.tintColor = UIColor.white.withAlphaComponent(0.7)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let badge: UILabel = {
        let label = UILabel()
        label.text = "LIVE"
        label.font = .systemFont(ofSize: 11, weight: .bold)
        label.textColor = .white
        label.textAlignment = .center
        label.backgroundColor = .liveStroke
        label.layer.cornerRadius = 3
        label.layer.masksToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        layer.cornerRadius = 10
        layer.borderWidth = 2
        layer.borderColor = UIColor.liveStroke.cgColor
        backgroundColor = .mediaPlaceholder
        isUserInteractionEnabled = false
        isHidden = true
        translatesAutoresizingMaskIntoConstraints = true
        addSubview(imageView)
        addSubview(symbolView)
        addSubview(badge)
        let symbolSide: CGFloat = 18
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            symbolView.centerXAnchor.constraint(equalTo: centerXAnchor),
            symbolView.centerYAnchor.constraint(equalTo: centerYAnchor),
            symbolView.widthAnchor.constraint(equalToConstant: symbolSide),
            symbolView.heightAnchor.constraint(equalToConstant: symbolSide),
            badgeLeading, badgeTop, badgeWidth, badgeHeight
        ])
    }

    private lazy var badgeLeading = badge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4)
    private lazy var badgeTop = badge.topAnchor.constraint(equalTo: topAnchor, constant: 4)
    private lazy var badgeWidth = badge.widthAnchor.constraint(equalToConstant: 28)
    private lazy var badgeHeight = badge.heightAnchor.constraint(equalToConstant: 12)

    /// Badge metrics for a card `width` points wide: the small ribbon thumb keeps
    /// the compact badge, a grid-sized card gets one that reads at a glance and
    /// sits clear of the rounded corner.
    static func badgeMetrics(forWidth width: CGFloat)
        -> (inset: CGFloat, size: CGSize, fontSize: CGFloat, corner: CGFloat) {
        width >= 120
            ? (10, CGSize(width: 46, height: 22), 13, 6)
            : (4, CGSize(width: 28, height: 12), 11, 3)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let metrics = Self.badgeMetrics(forWidth: bounds.width)
        guard badgeWidth.constant != metrics.size.width else { return }
        badgeLeading.constant = metrics.inset
        badgeTop.constant = metrics.inset
        badgeWidth.constant = metrics.size.width
        badgeHeight.constant = metrics.size.height
        badge.font = .systemFont(ofSize: metrics.fontSize, weight: .bold)
        badge.layer.cornerRadius = metrics.corner
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Updates still, fallback symbol, and VoiceOver for the current program.
    func configure(image: UIImage?, symbol: String?, fill: UIColor, title: String = "") {
        imageView.image = image
        imageView.isHidden = image == nil
        if let symbol {
            let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
            symbolView.image = UIImage(systemName: symbol, withConfiguration: config)
        } else {
            symbolView.image = nil
        }
        symbolView.isHidden = image != nil
        backgroundColor = fill
        accessibilityLabel = "On AirPlay"
        accessibilityValue = title
    }
}
