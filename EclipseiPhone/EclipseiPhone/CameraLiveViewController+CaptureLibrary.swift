//
//  CameraLiveViewController+CaptureLibrary.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Filing captures into the Eclipse library

extension CameraLiveViewController {

    /// JPEG quality for the library copy of a still; Photos keeps the original.
    private static let stillJPEGQuality: CGFloat = 0.95

    /// Files a still in the Eclipse library, and in the Show the camera was opened from.
    ///
    /// This is in addition to the Photos save, not instead of it: without an in-app copy
    /// a capture can only reach a Show by being re-imported through the library picker.
    func fileStillInLibrary(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: Self.stillJPEGQuality) else {
            return
        }
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).jpg")
        do {
            try data.write(to: temp)
        } catch {
            return
        }
        registerCapture(at: temp, isVideo: false, duration: 0, removingSource: true)
    }

    /// Files a finished movie, copying from the Caches file kept for in-app review.
    func fileMovieInLibrary(at previewURL: URL, duration: TimeInterval) {
        // The review file is the camera UI's, so it outlives this copy.
        Task { @MainActor in
            let measured = await VideoPosterFrame.durationSeconds(at: previewURL)
            let resolved = measured > 0.05 ? measured : duration
            registerCapture(
                at: previewURL, isVideo: true, duration: resolved, removingSource: false
            )
        }
    }

    // MARK: - Private

    private func registerCapture(
        at url: URL,
        isVideo: Bool,
        duration: TimeInterval,
        removingSource: Bool
    ) {
        CaptureStore.shared.addLocalCapture(
            fileURL: url,
            isVideo: isVideo,
            duration: duration,
            showId: captureDestinationShowId
        ) { _ in
            if removingSource {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
