//
//  PhotoImportLoader.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import UniformTypeIdentifiers

/// Loads picked Photos assets, surfacing the iCloud download that `NSItemProvider`
/// performs on our behalf.
///
/// Every load returns a `Progress` before any bytes arrive, and that object is the
/// only window into an iCloud download's state: how far along it is, and whether
/// it can be called off. Each entry point here hands it to `onStart` instead of
/// discarding it, which is what lets the UI show a determinate bar and a working
/// Cancel instead of an unbounded dead gap.
enum PhotoImportLoader {

    /// Loads a picked still at full resolution.
    ///
    /// Starting the load is main-actor work so `onStart` can hand the `Progress`
    /// straight to the UI that tracks it. The wait itself is a suspension, and the
    /// bytes are written by the photo library out of process, so nothing here
    /// occupies the main thread while the download runs.
    ///
    /// - Parameter onStart: Receives the download's `Progress`, called before the
    ///   first suspension.
    @MainActor
    static func loadImage(
        from provider: NSItemProvider,
        onStart: @MainActor (Progress) -> Void
    ) async -> Result<UIImage, PhotoImportFailure> {
        await withCheckedContinuation { continuation in
            let progress = provider.loadObject(ofClass: UIImage.self) { object, error in
                if let image = object as? UIImage {
                    continuation.resume(returning: .success(image))
                } else {
                    continuation.resume(returning: .failure(.classify(error)))
                }
            }
            onStart(progress)
        }
    }

    /// Loads a picked movie and copies it somewhere it will survive.
    ///
    /// The provider deletes its own copy the moment the completion handler
    /// returns, so the copy happens inside the handler — off the main thread,
    /// where the handler runs.
    ///
    /// - Parameter onStart: Receives the download's `Progress`, called before the
    ///   first suspension.
    @MainActor
    static func loadMovie(
        from provider: NSItemProvider,
        onStart: @MainActor (Progress) -> Void
    ) async -> Result<URL, PhotoImportFailure> {
        await withCheckedContinuation { continuation in
            let progress = provider.loadFileRepresentation(
                forTypeIdentifier: UTType.movie.identifier
            ) { url, error in
                guard let url else {
                    continuation.resume(returning: .failure(.classify(error)))
                    return
                }
                guard let copy = copyToTemporary(url) else {
                    continuation.resume(returning: .failure(.unreadable))
                    return
                }
                continuation.resume(returning: .success(copy))
            }
            onStart(progress)
        }
    }

    /// True when the pick is a movie.
    static func isMovie(_ provider: NSItemProvider) -> Bool {
        provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
    }

    /// True when the pick can be loaded as a still.
    ///
    /// This answers "what type is it", not "is it on the device" — a pick whose
    /// original is still in iCloud reports true here and downloads on load.
    static func isImage(_ provider: NSItemProvider) -> Bool {
        provider.canLoadObject(ofClass: UIImage.self)
    }

    /// Copies a provider's temporary file into our own temporary directory.
    private static func copyToTemporary(_ sourceURL: URL) -> URL? {
        let ext = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            return destination
        } catch {
            return nil
        }
    }
}
