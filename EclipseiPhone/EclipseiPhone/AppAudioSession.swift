//
//  AppAudioSession.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation
import Foundation
import os

/// App-wide audio session rules: Eclipse never stops music another app (Spotify, Apple
/// Music…) is playing just by being open, showing the camera, or playing silent video.
///
/// - Launch: `.ambient`, which mixes with other apps. Without this the app runs on the
///   system default `soloAmbient`, and the first (even muted) `AVPlayer` or the camera
///   stops the other app's music.
/// - Audible video: `.playback` + `.mixWithOthers` (see `PresentationAudioSession`),
///   unless Pause Music for Video is on.
/// - Camera recording: `.playAndRecord` + `.mixWithOthers` set here, because the capture
///   session's own automatic setup is not mixable.
enum AppAudioSession {

    private static let logger = Logger(
        subsystem: "com.eclipseapp.ios",
        category: "AppAudioSession"
    )

    /// Category + options the app is in outside recording, restored after a recording.
    private static let lock = NSLock()
    private static var savedBeforeRecording: (
        category: AVAudioSession.Category,
        mode: AVAudioSession.Mode,
        options: AVAudioSession.CategoryOptions
    )?

    /// Call once at launch. Does not activate the session.
    static func configureAtLaunch() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        } catch {
            logger.error("Launch audio category failed: \(error.localizedDescription)")
        }
    }

    /// Options for presentation `.playback`: mix with other apps unless the user asked
    /// for music to pause for video.
    static func presentationOptions(pauseMusicForVideo: Bool) -> AVAudioSession.CategoryOptions {
        pauseMusicForVideo ? [] : [.mixWithOthers]
    }

    /// Before adding the mic to the capture session (when the full-screen camera opens):
    /// record without stopping other audio.
    /// Safe to call from any queue.
    static func beginRecording() {
        let session = AVAudioSession.sharedInstance()
        let options: AVAudioSession.CategoryOptions =
            [.mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP]
        lock.lock()
        if savedBeforeRecording == nil {
            savedBeforeRecording = (session.category, session.mode, session.categoryOptions)
        }
        lock.unlock()
        if session.category == .playAndRecord, session.categoryOptions == options {
            return
        }
        // Keep the hardware sample rate other apps are playing at: a rate change is what
        // makes their music drop out while the route is rebuilt.
        let currentRate = session.sampleRate
        do {
            // `.default` mode: `.videoRecording` switches mic processing, another re-route.
            try session.setCategory(.playAndRecord, mode: .default, options: options)
            if currentRate > 0 {
                try? session.setPreferredSampleRate(currentRate)
            }
            try session.setActive(true)
        } catch {
            logger.error("Recording audio session failed: \(error.localizedDescription)")
        }
    }

    /// After the mic is removed: go back to the category used before recording.
    static func endRecording() {
        lock.lock()
        let saved = savedBeforeRecording
        savedBeforeRecording = nil
        lock.unlock()
        guard let saved else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(
                saved.category,
                mode: saved.mode,
                options: saved.options
            )
        } catch {
            logger.error("Restoring audio session failed: \(error.localizedDescription)")
        }
    }
}
