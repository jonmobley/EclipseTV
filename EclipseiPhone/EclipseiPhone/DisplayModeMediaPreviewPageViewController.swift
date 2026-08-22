//
//  DisplayModeMediaPreviewPageViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation
import UIKit

/// One Display Mode fill panel (Screensaver / Background) inside a Preview pager.
final class DisplayModeMediaPreviewPageViewController: UIViewController {

    let index: Int

    /// Called when pinch/double-tap zoom crosses the filled scale.
    var onZoomedChanged: ((Bool) -> Void)?

    private let fileURL: URL
    private let isVideo: Bool
    private let usesSeamlessLoop: Bool

    private let panelView: UIView = {
        let view = UIView()
        view.backgroundColor = .black
        view.clipsToBounds = true
        view.layer.cornerRadius = 16
        return view
    }()

    private let zoomView: ZoomableImageView = {
        let view = ZoomableImageView()
        view.minimumFit = .cover
        return view
    }()

    private var loopPlayer: SeamlessLoopPlayerView?
    private var simplePlayer: AVPlayer?
    private var simplePlayerLayer: AVPlayerLayer?
    private var endObserver: NSObjectProtocol?

    /// - Parameters:
    ///   - fileURL: Local still or video file.
    ///   - isVideo: Plays video instead of showing a still.
    ///   - usesSeamlessLoop: Screensaver dual-player crossfade.
    ///   - index: Page index in the hosting gallery.
    init(fileURL: URL, isVideo: Bool, usesSeamlessLoop: Bool, index: Int) {
        self.fileURL = fileURL
        self.isVideo = isVideo
        self.usesSeamlessLoop = usesSeamlessLoop && isVideo
        self.index = index
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.addSubview(panelView)
        if isVideo {
            setupVideo()
        } else {
            setupImage()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        panelView.frame = ExternalOutputSettings.displayModePanelRect(in: view.bounds)
        zoomView.frame = panelView.bounds
        loopPlayer?.frame = panelView.bounds
        simplePlayerLayer?.frame = panelView.bounds
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        loopPlayer?.play()
        simplePlayer?.play()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        pausePlayback()
    }

    /// Stops Screensaver playback when this page is no longer current.
    func pausePlayback() {
        loopPlayer?.stop()
        simplePlayer?.pause()
    }

    /// Restores fill framing after the page is no longer current.
    func resetZoom() {
        zoomView.resetZoom(animated: false)
    }

    // MARK: - Setup

    private func setupImage() {
        zoomView.image = UIImage(contentsOfFile: fileURL.path)
        zoomView.onZoomedChanged = { [weak self] zoomed in
            self?.onZoomedChanged?(zoomed)
        }
        panelView.addSubview(zoomView)
    }

    private func setupVideo() {
        if usesSeamlessLoop {
            let player = SeamlessLoopPlayerView(url: fileURL)
            panelView.addSubview(player)
            loopPlayer = player
            return
        }
        let player = AVPlayer(url: fileURL)
        player.isMuted = false
        player.actionAtItemEnd = .none
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        panelView.layer.addSublayer(layer)
        simplePlayer = player
        simplePlayerLayer = layer
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }
    }
}
