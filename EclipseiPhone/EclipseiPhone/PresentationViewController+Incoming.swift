//
//  PresentationViewController+Incoming.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import AVFoundation
import WebKit
import PDFKit

// MARK: - Incoming Overlay Content

extension PresentationViewController {

    /// Builds the next source inside `transitionOverlayContainer` (underlay stays live).
    func installIncoming(_ source: PresentationSource, generation: Int) {
        switch source.content {
        case .image(let url, let fill):
            installIncomingImage(url: url, fill: fill, generation: generation)
        case .video(let url, let isLooping, let isMuted):
            installIncomingVideo(
                url: url, isLooping: isLooping, isMuted: isMuted, generation: generation
            )
        case .camera:
            installIncomingCamera(generation: generation)
        case .web(let url):
            installIncomingWeb(url: url, generation: generation)
        case .pdf(let url):
            installIncomingPDF(url: url, generation: generation)
        case .black:
            // Overlay is already black.
            notifyIfCurrent(generation)
        case .unavailable(let thumbnail, _):
            installIncomingImage(uiImage: thumbnail, generation: generation)
        }
    }

    // MARK: - Image

    private func installIncomingImage(url: URL, fill: Bool, generation: Int) {
        let imageView = makeIncomingImageView()
        imageView.contentMode = fill || LogoStore.shared.isLogoFileURL(url)
            ? .scaleAspectFill : .scaleAspectFit

        if url.isFileURL {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let image = UIImage(contentsOfFile: url.path)
                DispatchQueue.main.async {
                    guard let self, generation == self.transitionGeneration else { return }
                    imageView.image = image
                    self.notifyIfCurrent(generation)
                }
            }
        } else {
            incomingImageRequest = RemoteImageLoader.shared.loadImage(from: url) { [weak self] image in
                guard let self, generation == self.transitionGeneration else { return }
                imageView.image = image
                self.notifyIfCurrent(generation)
            }
        }
    }

    private func installIncomingImage(uiImage: UIImage?, generation: Int) {
        let imageView = makeIncomingImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.image = uiImage
        notifyIfCurrent(generation)
    }

    private func makeIncomingImageView() -> UIImageView {
        let host = makeIncomingMediaHost()
        let imageView = UIImageView()
        imageView.clipsToBounds = true
        imageView.backgroundColor = .black
        imageView.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: host.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: host.trailingAnchor)
        ])
        incomingImageView = imageView
        layoutIncomingMediaHost()
        return imageView
    }

    // MARK: - Video

    private func installIncomingVideo(
        url: URL, isLooping: Bool, isMuted: Bool, generation: Int
    ) {
        let host = makeIncomingMediaHost()
        configureAudioSession(muted: isMuted)

        let player = AVPlayer(url: url)
        player.isMuted = isMuted
        player.actionAtItemEnd = isLooping ? .none : .pause

        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        host.layer.insertSublayer(layer, at: 0)

        incomingPlayer = player
        incomingPlayerLayer = layer
        layoutIncomingMediaHost()

        if isLooping {
            incomingLoopObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { [weak player] _ in
                player?.seek(to: .zero)
                player?.play()
            }
        }

        if let item = player.currentItem {
            if item.status == .readyToPlay {
                notifyIfCurrent(generation)
            } else {
                incomingVideoReadyObservation = item.observe(\.status, options: [.new]) {
                    [weak self] item, _ in
                    guard item.status == .readyToPlay || item.status == .failed else { return }
                    self?.incomingVideoReadyObservation = nil
                    self?.notifyIfCurrent(generation)
                }
            }
        } else {
            notifyIfCurrent(generation)
        }
        player.play()
    }

    // MARK: - Camera

    private func installIncomingCamera(generation: Int) {
        let preview = CameraPreviewView()
        preview.translatesAutoresizingMaskIntoConstraints = true
        transitionOverlayContainer.addSubview(preview)
        incomingCameraPreview = preview

        let frameView = UIImageView()
        frameView.contentMode = .scaleAspectFit
        frameView.clipsToBounds = true
        frameView.isUserInteractionEnabled = false
        frameView.translatesAutoresizingMaskIntoConstraints = true
        frameView.image = CameraFrameStore.shared.selectedImage
        frameView.isHidden = frameView.image == nil
        transitionOverlayContainer.addSubview(frameView)
        incomingCameraFrameOverlay = frameView

        let gravity: AVLayerVideoGravity =
            ExternalOutputSettings.isVerticalMode ? .resizeAspectFill : .resizeAspect
        preview.attach(
            session: CameraManager.shared.captureSession,
            videoGravity: gravity
        )
        preview.syncDisplayModeOrientation()
        layoutIncomingCamera()

        if CameraManager.shared.isSessionRunning {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.notifyIfCurrent(generation)
            }
            return
        }

        var attempts = 0
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            attempts += 1
            let ready = CameraManager.shared.isSessionRunning || attempts >= 20
            guard ready else { return }
            timer.invalidate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.notifyIfCurrent(generation)
            }
        }
    }

    // MARK: - Web

    private func installIncomingWeb(url: URL, generation: Int) {
        let view = WKWebView(frame: .zero, configuration: EclipseWebKit.makeConfiguration())
        view.customUserAgent = Self.mobileUserAgent
        view.scrollView.showsVerticalScrollIndicator = false
        view.scrollView.showsHorizontalScrollIndicator = false
        view.scrollView.bounces = false
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.isOpaque = false
        view.backgroundColor = .black
        view.scrollView.backgroundColor = .black
        view.isUserInteractionEnabled = false
        view.translatesAutoresizingMaskIntoConstraints = true

        let nav = IncomingWebNavigation { [weak self] in
            self?.notifyIfCurrent(generation)
        }
        view.navigationDelegate = nav
        incomingWebNavigation = nav
        incomingWebView = view
        transitionOverlayContainer.addSubview(view)
        layoutIncomingWeb()
        view.load(URLRequest(url: url))
    }

    // MARK: - PDF

    private func installIncomingPDF(url: URL, generation: Int) {
        let view = PDFView()
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.autoScales = true
        view.backgroundColor = .black
        view.isUserInteractionEnabled = false
        view.translatesAutoresizingMaskIntoConstraints = true
        incomingPDFView = view
        transitionOverlayContainer.addSubview(view)
        layoutIncomingPDF()

        if let document = PDFDocument(url: url), document.pageCount > 0 {
            view.document = document
            view.autoScales = true
        }
        notifyIfCurrent(generation)
    }

    // MARK: - Layout

    private func makeIncomingMediaHost() -> UIView {
        let host = UIView()
        host.backgroundColor = .black
        host.translatesAutoresizingMaskIntoConstraints = true
        transitionOverlayContainer.addSubview(host)
        incomingMediaHost = host
        return host
    }

    func layoutIncomingOverlayContent() {
        layoutIncomingMediaHost()
        layoutIncomingCamera()
        layoutIncomingWeb()
        layoutIncomingPDF()
    }

    private func layoutIncomingMediaHost() {
        guard let host = incomingMediaHost else { return }
        applyRotatedLayout(to: host, in: transitionOverlayContainer, scale: 1)
        incomingPlayerLayer?.frame = host.bounds
    }

    private func layoutIncomingCamera() {
        guard let preview = incomingCameraPreview else { return }
        applyRotatedLayout(to: preview, in: transitionOverlayContainer, scale: 1)
        preview.syncDisplayModeOrientation()
        if let frameView = incomingCameraFrameOverlay {
            applyRotatedLayout(to: frameView, in: transitionOverlayContainer, scale: 1)
            transitionOverlayContainer.bringSubviewToFront(frameView)
        }
    }

    /// Syncs the incoming-transition camera frame when the store changes mid-hold.
    func refreshIncomingCameraFrameOverlay() {
        guard let frameView = incomingCameraFrameOverlay else { return }
        frameView.image = CameraFrameStore.shared.selectedImage
        frameView.isHidden = frameView.image == nil
        layoutIncomingCamera()
    }

    private func layoutIncomingWeb() {
        guard let web = incomingWebView else { return }
        Self.applyWebOutputLayout(to: web, in: transitionOverlayContainer)
    }

    private func layoutIncomingPDF() {
        guard let pdf = incomingPDFView else { return }
        applyRotatedLayout(to: pdf, in: transitionOverlayContainer, scale: 1)
        pdf.autoScales = true
    }

    private func notifyIfCurrent(_ generation: Int) {
        guard generation == transitionGeneration else { return }
        notifyContentReadyForTransition()
    }
}

// MARK: - Incoming Web Navigation

/// Tiny delegate so overlay WKWebView can signal first paint without fighting the
/// primary web view's navigation delegate.
private final class IncomingWebNavigation: NSObject, WKNavigationDelegate {
    private let onDone: () -> Void
    private var didSignal = false

    init(onDone: @escaping () -> Void) {
        self.onDone = onDone
    }

    private func signal() {
        guard !didSignal else { return }
        didSignal = true
        onDone()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        signal()
    }

    func webView(
        _ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error
    ) {
        signal()
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        signal()
    }
}
