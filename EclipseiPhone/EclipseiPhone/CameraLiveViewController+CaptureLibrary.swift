//
//  CameraLiveViewController+CaptureLibrary.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Filing captures into the Eclipse library

extension CameraLiveViewController {

    /// Files a still in the Eclipse library, and in the Show the camera was opened from.
    ///
    /// This is in addition to the Photos save, not instead of it: without an in-app copy
    /// a capture can only reach a Show by being re-imported through the library picker.
    func fileStillInLibrary(_ image: UIImage) {
        CameraCaptureFiling.fileStill(image, showId: captureDestinationShowId)
    }

    /// Files a finished movie, copying from the Caches file kept for in-app review.
    func fileMovieInLibrary(at previewURL: URL, duration: TimeInterval) {
        CameraCaptureFiling.fileMovie(
            at: previewURL, duration: duration, showId: captureDestinationShowId
        )
    }
}

/// Files camera captures in the Eclipse library (and a Show), shared by the full-screen
/// camera and the grid's live camera hero.
@MainActor
enum CameraCaptureFiling {

    /// JPEG quality for the library copy of a still; Photos keeps the original.
    private static let stillJPEGQuality: CGFloat = 0.95

    static func fileStill(_ image: UIImage, showId: UUID?) {
        guard let data = image.jpegData(compressionQuality: stillJPEGQuality) else {
            return
        }
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).jpg")
        do {
            try data.write(to: temp)
        } catch {
            return
        }
        register(at: temp, isVideo: false, duration: 0, showId: showId, removingSource: true)
    }

    static func fileMovie(at previewURL: URL, duration: TimeInterval, showId: UUID?) {
        // The review file is the camera UI's, so it outlives this copy.
        Task { @MainActor in
            let measured = await VideoPosterFrame.durationSeconds(at: previewURL)
            let resolved = measured > 0.05 ? measured : duration
            register(
                at: previewURL, isVideo: true, duration: resolved, showId: showId,
                removingSource: false
            )
        }
    }

    private static func register(
        at url: URL,
        isVideo: Bool,
        duration: TimeInterval,
        showId: UUID?,
        removingSource: Bool
    ) {
        CaptureStore.shared.addLocalCapture(
            fileURL: url,
            isVideo: isVideo,
            duration: duration,
            showId: showId
        ) { _ in
            if removingSource {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
