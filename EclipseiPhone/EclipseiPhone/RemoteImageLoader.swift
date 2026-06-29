//
//  RemoteImageLoader.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

// RemoteImageLoader.swift
import UIKit
import ImageIO
import os.log

/// A cancellable in-flight image load. Reused cells cancel their previous request before
/// starting a new one (and in `prepareForReuse`).
final class RemoteImageRequest {
    fileprivate var task: URLSessionDataTask?
    fileprivate(set) var isCancelled = false

    func cancel() {
        isCancelled = true
        task?.cancel()
    }
}

/// Loads images from HTTPS URLs for the album browser, with an in-memory cache, a
/// persistent disk cache, and optional downsampling for grid thumbnails.
///
/// This is the iPhone companion's only outbound internet networking.
final class RemoteImageLoader {

    static let shared = RemoteImageLoader()

    private let session: URLSession
    private let memoryCache = NSCache<NSString, UIImage>()
    private let diskDirectory: URL
    private let ioQueue = DispatchQueue(label: "com.eclipseapp.ios.RemoteImageLoader", qos: .utility)
    private let logger = Logger(subsystem: "com.eclipseapp.ios", category: "RemoteImageLoader")

    init(session: URLSession = .shared) {
        self.session = session
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        diskDirectory = base.appendingPathComponent("AlbumThumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskDirectory, withIntermediateDirectories: true)
        memoryCache.countLimit = 200
    }

    // MARK: - Public

    /// Loads an image for `url`, optionally downsampled to fit `targetSize` (points).
    /// `completion` is always called on the main thread (skipped if the request is
    /// cancelled). Returns a token the caller can cancel on reuse.
    @discardableResult
    func loadImage(from url: URL,
                   targetSize: CGSize? = nil,
                   completion: @escaping (UIImage?) -> Void) -> RemoteImageRequest {
        let request = RemoteImageRequest()
        let key = Self.cacheKey(url: url, targetSize: targetSize) as NSString

        if let cached = memoryCache.object(forKey: key) {
            DispatchQueue.main.async { if !request.isCancelled { completion(cached) } }
            return request
        }

        let fileURL = diskDirectory.appendingPathComponent(Self.fileName(for: key as String))
        ioQueue.async { [weak self] in
            guard let self = self, !request.isCancelled else { return }

            if let data = try? Data(contentsOf: fileURL),
               let image = self.makeImage(from: data, targetSize: targetSize) {
                self.memoryCache.setObject(image, forKey: key)
                DispatchQueue.main.async { if !request.isCancelled { completion(image) } }
                return
            }

            let task = self.session.dataTask(with: url) { [weak self] data, response, error in
                guard let self = self else { return }
                guard let data = data, error == nil,
                      let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    if (error as NSError?)?.code == NSURLErrorCancelled { return }
                    DispatchQueue.main.async { if !request.isCancelled { completion(nil) } }
                    return
                }
                self.ioQueue.async { try? data.write(to: fileURL, options: .atomic) }
                guard let image = self.makeImage(from: data, targetSize: targetSize) else {
                    DispatchQueue.main.async { if !request.isCancelled { completion(nil) } }
                    return
                }
                self.memoryCache.setObject(image, forKey: key)
                DispatchQueue.main.async { if !request.isCancelled { completion(image) } }
            }
            request.task = task
            if !request.isCancelled { task.resume() }
        }
        return request
    }

    // MARK: - Private

    /// Decodes `data`, downsampling to `targetSize` when provided (keeps memory low for
    /// grid thumbnails); otherwise decodes at full size for fullscreen preview.
    private func makeImage(from data: Data, targetSize: CGSize?) -> UIImage? {
        guard let targetSize = targetSize else { return UIImage(data: data) }

        let scale = UIScreen.main.scale
        let maxPixel = max(targetSize.width, targetSize.height) * scale
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: cgImage)
    }

    private static func cacheKey(url: URL, targetSize: CGSize?) -> String {
        if let size = targetSize {
            return "\(url.absoluteString)|\(Int(size.width))x\(Int(size.height))"
        }
        return "\(url.absoluteString)|full"
    }

    /// Maps a cache key to a filesystem-safe file name.
    private static func fileName(for key: String) -> String {
        let safe = key.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "_" }
        return String(safe) + ".img"
    }
}
