//
//  PlacedMediaOverlay.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//
//  Description: A photo or looping, muted video drawn as a layered overlay at
//               its normalized center and width (the Mac's image / video
//               overlay placement).
//  Thread Safety: Main thread only - SwiftUI / UIKit views.
//

import AVFoundation
import SwiftUI
import UIKit

// MARK: - PlacedMediaOverlay

/// Positions one media overlay inside the program frame.
struct PlacedMediaOverlay: View {

    // MARK: - Properties

    let entry: MediaOverlayEntry
    let contentFrame: CGRect
    /// Called with the overlay's drawn frame in the layer's coordinate space
    /// (`LiveOverlayLayerView.coordinateSpace`), for touch hit-testing.
    var onFrame: ((CGRect) -> Void)?

    /// Width / height of the media; 16:9 until the file is read.
    @State private var aspect: CGFloat = 16.0 / 9.0
    @State private var image: UIImage?

    private var fileURL: URL? {
        LocalMediaStore.shared.localURL(forId: entry.itemId)
    }

    // MARK: - Body

    var body: some View {
        let size = Self.displaySize(entry: entry, aspect: aspect, in: contentFrame)
        content
            .frame(width: size.width, height: size.height)
            .onGeometryChange(for: CGRect.self) {
                $0.frame(in: .named(LiveOverlayLayerView.coordinateSpace))
            } action: { onFrame?($0) }
            .position(
                x: contentFrame.minX + entry.centerX * contentFrame.width,
                y: contentFrame.minY + entry.centerY * contentFrame.height
            )
            .task(id: entry.itemId) { await loadMedia() }
    }

    // MARK: - Layout

    /// On-screen size: `scale` of the frame width, height from the media aspect.
    static func displaySize(entry: MediaOverlayEntry, aspect: CGFloat, in frame: CGRect) -> CGSize {
        let width = frame.width * CGFloat(entry.clamped().scale)
        return CGSize(width: width, height: width / max(aspect, 0.01))
    }

    // MARK: - Private

    @ViewBuilder
    private var content: some View {
        if entry.isVideo, let fileURL {
            LoopingVideoView(url: fileURL)
        } else if let image {
            Image(uiImage: image).resizable()
        } else {
            Color.clear
        }
    }

    private func loadMedia() async {
        guard let fileURL else { return }
        if entry.isVideo {
            let asset = AVURLAsset(url: fileURL)
            guard let track = try? await asset.loadTracks(withMediaType: .video).first,
                  let (natural, transform) = try? await track.load(.naturalSize, .preferredTransform)
            else { return }
            let size = natural.applying(transform)
            if size.height != 0 { aspect = abs(size.width / size.height) }
        } else if let loaded = UIImage(contentsOfFile: fileURL.path), loaded.size.height > 0 {
            image = loaded
            aspect = loaded.size.width / loaded.size.height
        }
    }
}

// MARK: - LoopingVideoView

/// A muted video that loops forever, for video overlays.
private struct LoopingVideoView: UIViewRepresentable {

    let url: URL

    func makeUIView(context: Context) -> LoopingPlayerView {
        LoopingPlayerView(url: url)
    }

    func updateUIView(_ uiView: LoopingPlayerView, context: Context) {}
}

/// Hosts an `AVPlayerLayer` backed by an `AVPlayerLooper`.
private final class LoopingPlayerView: UIView {

    override class var layerClass: AnyClass { AVPlayerLayer.self }

    private let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?

    init(url: URL) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        player.isMuted = true
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        (layer as? AVPlayerLayer)?.player = player
        (layer as? AVPlayerLayer)?.videoGravity = .resizeAspect
        player.play()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        player.pause()
    }
}
