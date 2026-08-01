//
//  CameraMirrorView.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation
import UIKit

/// Live camera view fed by `CameraManager`'s frame tap rather than the capture session.
///
/// A capture session drives exactly one `AVCaptureVideoPreviewLayer`: whichever layer
/// binds to the session last takes the preview connection and every earlier one goes
/// black. AirPlay keeps that single hardware layer while live, so the phone panel
/// renders here instead — same frames, no competition for the connection.
///
/// Frames arrive in sensor orientation. Callers rotate the view using the active
/// lens’s horizon capture angle so front/back stay upright.
final class CameraMirrorView: UIView {

    override class var layerClass: AnyClass {
        AVSampleBufferDisplayLayer.self
    }

    /// True while registered with `CameraManager` for frames.
    private(set) var isMirroring = false

    /// Invoked once on the main queue after the first sample is enqueued.
    var onFirstFrame: (() -> Void)?

    var videoGravity: AVLayerVideoGravity {
        get { displayLayer.videoGravity }
        set { displayLayer.videoGravity = newValue }
    }

    private var displayLayer: AVSampleBufferDisplayLayer {
        layer as! AVSampleBufferDisplayLayer
    }

    /// Resolved once at init so the frame queue never reads `UIView.layer` off main.
    private var renderer: AVSampleBufferVideoRenderer!
    private var hasDeliveredFirstFrame = false

    // MARK: - Lifecycle

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func commonInit() {
        backgroundColor = .black
        isUserInteractionEnabled = false
        displayLayer.videoGravity = .resizeAspectFill
        renderer = displayLayer.sampleBufferRenderer
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDecodeFailure(_:)),
            name: AVSampleBufferVideoRenderer.didFailToDecodeNotification,
            object: nil
        )
    }

    // MARK: - Mirroring

    /// Starts receiving frames from the shared camera frame tap.
    func startMirroring() {
        guard !isMirroring else { return }
        isMirroring = true
        hasDeliveredFirstFrame = false
        renderer.flush()
        CameraManager.shared.addFrameMirror(self)
    }

    /// Stops receiving frames and drops anything still queued.
    func stopMirroring() {
        guard isMirroring else { return }
        isMirroring = false
        onFirstFrame = nil
        CameraManager.shared.removeFrameMirror(self)
        renderer.flush()
    }

    /// Displays `sampleBuffer` immediately. Called on `CameraManager.frameQueue`.
    ///
    /// The renderer has no control timebase, so each sample is tagged to display on
    /// arrival instead of being scheduled against a clock.
    func enqueue(_ sampleBuffer: CMSampleBuffer) {
        guard let renderer, renderer.isReadyForMoreMediaData else { return }
        Self.markDisplayImmediately(sampleBuffer)
        renderer.enqueue(sampleBuffer)
        notifyFirstFrameIfNeeded()
    }

    private func notifyFirstFrameIfNeeded() {
        guard !hasDeliveredFirstFrame else { return }
        hasDeliveredFirstFrame = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let callback = self.onFirstFrame
            self.onFirstFrame = nil
            callback?()
        }
    }

    // MARK: - Private

    private static func markDisplayImmediately(_ sampleBuffer: CMSampleBuffer) {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: true
        ) as? [NSMutableDictionary],
            let first = attachments.first
        else {
            return
        }
        first[kCMSampleAttachmentKey_DisplayImmediately] = true
    }

    @objc private func handleDecodeFailure(_ notification: Notification) {
        guard let failed = notification.object as? AVSampleBufferVideoRenderer,
              failed === renderer
        else {
            return
        }
        renderer.flush()
    }
}
