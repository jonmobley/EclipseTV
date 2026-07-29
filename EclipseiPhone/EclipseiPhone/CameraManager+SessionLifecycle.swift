//
//  CameraManager+SessionLifecycle.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation
import UIKit

// MARK: - Active-Gated Start + Interruption Recovery

extension CameraManager {

    /// Max retries when `startRunning` returns without a live session.
    private static let maxStartAttempts = 6

    /// Starts capture when the app is active; retries if the session fails to run.
    /// - Parameters:
    ///   - attempt: Zero-based retry index.
    ///   - completion: Invoked on the main queue after a successful start or final failure.
    func startCaptureIfPossible(attempt: Int, completion: @escaping () -> Void) {
        guard wantsSessionRunning else {
            DispatchQueue.main.async(execute: completion)
            return
        }

        guard UIApplication.shared.applicationState == .active else {
            waitForActiveThenStart(completion: completion)
            return
        }

        let session = captureSession
        sessionQueue.async { [weak self, session] in
            guard let self else {
                DispatchQueue.main.async(execute: completion)
                return
            }
            if !session.isRunning {
                session.startRunning()
            }
            let isRunning = session.isRunning
            DispatchQueue.main.async {
                self.publishSessionRunning(isRunning)
                guard self.wantsSessionRunning else {
                    completion()
                    return
                }
                if isRunning {
                    completion()
                    return
                }
                self.retryStartIfNeeded(attempt: attempt, completion: completion)
            }
        }
    }

    /// Installs interruption / runtime-error observers once.
    func installSessionRecoveryIfNeeded() {
        guard !didInstallSessionRecovery else { return }
        didInstallSessionRecovery = true

        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(handleCaptureRuntimeError(_:)),
            name: AVCaptureSession.runtimeErrorNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleCaptureInterrupted(_:)),
            name: AVCaptureSession.wasInterruptedNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleCaptureInterruptionEnded(_:)),
            name: AVCaptureSession.interruptionEndedNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActiveForCapture),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleAppDidEnterBackgroundForCapture),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }

    /// Stops capture for backgrounding while remembering that a caller still wants it.
    ///
    /// The system tears the session down when the app leaves the foreground. Without this
    /// the manager keeps publishing `isSessionRunning == true` over a dead session, so the
    /// home tile and AirPlay stage keep a frozen LIVE badge until something restarts it.
    func suspendCaptureForBackground() {
        clearActiveStartWait()
        closeOutRecordingIfNeeded()

        let session = captureSession
        sessionQueue.async { [weak self, session] in
            if session.isRunning {
                session.stopRunning()
            }
            self?.publishSessionRunning(false)
        }
    }

    /// Finishes any in-flight movie so the footage so far is saved rather than truncated.
    func closeOutRecordingIfNeeded() {
        guard isRecording else { return }
        logger.notice("Closing out recording because capture is going away")
        stopRecording()
    }

    /// Cancels any deferred start waiting on `didBecomeActive`.
    func clearActiveStartWait() {
        if let activeStartObserver {
            NotificationCenter.default.removeObserver(activeStartObserver)
            self.activeStartObserver = nil
        }
    }

    // MARK: - Private

    private func waitForActiveThenStart(completion: @escaping () -> Void) {
        clearActiveStartWait()
        activeStartObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.clearActiveStartWait()
            guard self.wantsSessionRunning else {
                completion()
                return
            }
            self.startCaptureIfPossible(attempt: 0, completion: completion)
        }
    }

    private func retryStartIfNeeded(attempt: Int, completion: @escaping () -> Void) {
        guard attempt + 1 < Self.maxStartAttempts else {
            logger.error("Camera session failed to start after \(Self.maxStartAttempts) attempts")
            completion()
            return
        }
        let delay = 0.12 * Double(attempt + 1)
        logger.debug("Camera start retry \(attempt + 1) in \(delay, format: .fixed(precision: 2))s")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.wantsSessionRunning else {
                completion()
                return
            }
            self.startCaptureIfPossible(attempt: attempt + 1, completion: completion)
        }
    }

    @objc func handleCaptureRuntimeError(_ notification: Notification) {
        guard wantsSessionRunning else { return }
        let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError
        logger.error(
            "Capture runtime error: \(error?.localizedDescription ?? "unknown", privacy: .public)"
        )
        startCaptureIfPossible(attempt: 0, completion: {})
    }

    @objc func handleCaptureInterrupted(_ notification: Notification) {
        let reason = (notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int)
            .flatMap(AVCaptureSession.InterruptionReason.init(rawValue:))
        logger.notice("Capture interrupted (reason \(reason?.rawValue ?? -1))")
        // The session has already stopped — a phone call, Siri, or another app took the
        // camera. Publish that so LIVE badges clear, and close out any movie in progress.
        publishSessionRunning(false)
        closeOutRecordingIfNeeded()
    }

    @objc func handleCaptureInterruptionEnded(_ notification: Notification) {
        guard wantsSessionRunning else { return }
        logger.debug("Capture interruption ended; restarting session")
        startCaptureIfPossible(attempt: 0, completion: {})
    }

    @objc func handleAppDidBecomeActiveForCapture() {
        guard wantsSessionRunning, !isSessionRunning else { return }
        startCaptureIfPossible(attempt: 0, completion: {})
    }

    @objc func handleAppDidEnterBackgroundForCapture() {
        suspendCaptureForBackground()
    }
}
