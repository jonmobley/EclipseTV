//
//  CameraKitSync.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import EclipsePhoneCameraProtocol
import OSLog
import UIKit

// MARK: - CameraKitSync

/// Downloads the Mac show's Camera Kit into `CameraKitStore` and sends
/// pictures added on the phone back to the Mac when the show allows it.
///
/// Uses the Camera Mode session's paired API client, so it only works while
/// that session is connected.
///
/// Thread safety: main actor only; network work runs in child tasks.
@MainActor
final class CameraKitSync {

    // MARK: - Properties

    static let shared = CameraKitSync()

    /// Supplies the paired client (set by Camera Mode).
    var clientProvider: () -> PhoneCameraAPIClient? = { nil }

    private var lastRevision = -1
    private var refreshTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.eclipseapp.ios", category: "CameraKit")

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Interface

    /// Refetches the kit (skips work when the revision is unchanged).
    /// - Parameter force: Refetch even when the revision matches.
    func refresh(force: Bool = false) {
        guard let client = clientProvider() else { return }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.load(using: client, force: force)
        }
    }

    /// Handles a Mac event; refetches on `KIT_CHANGED`.
    /// - Parameter data: Raw SSE JSON.
    func handleEvent(_ data: Data) {
        guard let message = try? JSONDecoder().decode(PhoneCameraKitChangedMessage.self, from: data),
              message.type == PhoneCameraMessageType.kitChanged.rawValue,
              message.revision != lastRevision else { return }
        refresh()
    }

    /// Stops syncing and forgets the kit.
    func reset() {
        refreshTask?.cancel()
        lastRevision = -1
        CameraKitStore.shared.clear()
    }

    /// Sends a picture to the Mac show (two-way kits only).
    /// - Parameters:
    ///   - image: Picture to send.
    ///   - kind: Frame (sent as PNG, keeps transparency) or still (JPEG).
    ///   - name: Optional card name.
    /// - Returns: True when the Mac accepted every chunk.
    @discardableResult
    func upload(_ image: UIImage, kind: PhoneCameraKitItem.Kind, name: String = "") async -> Bool {
        guard CameraKitStore.shared.isTwoWay, let client = clientProvider() else { return false }
        let isFrame = kind == .frame
        guard let data = isFrame ? image.pngData() : image.jpegData(compressionQuality: 0.9),
              data.count <= PhoneCameraKitRoute.maxUploadBytes else { return false }
        let plan = CameraKitUploadPlan(byteCount: data.count)
        let base = CameraKitUploadPlan.query(
            kind: kind, name: name, fileExtension: isFrame ? "png" : "jpg"
        )
        do {
            for index in 0..<plan.chunkCount {
                let path = "\(PhoneCameraKitRoute.upload)?\(base)&upload=\(plan.uploadId)"
                    + "&index=\(index)&count=\(plan.chunkCount)"
                try await client.postBinary(data.subdata(in: plan.range(of: index)), path: path)
            }
            return true
        } catch {
            logger.error("Kit upload failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Private Helpers

    private func load(using client: PhoneCameraAPIClient, force: Bool) async {
        do {
            let data = try await client.getData(path: PhoneCameraKitRoute.manifest, timeoutSeconds: 10)
            let manifest = try JSONDecoder().decode(PhoneCameraKitManifest.self, from: data)
            guard force || manifest.revision != lastRevision, !Task.isCancelled else { return }
            let pictures = await download(manifest.items, using: client)
            guard !Task.isCancelled else { return }
            lastRevision = manifest.revision
            CameraKitStore.shared.apply(manifest, pictures: pictures)
        } catch {
            // An older Mac has no /kit route; Camera Mode simply has no kit then.
            logger.notice("Kit fetch failed: \(error.localizedDescription)")
        }
    }

    /// Downloads pictures not already cached at their version.
    private func download(
        _ items: [PhoneCameraKitItem],
        using client: PhoneCameraAPIClient
    ) async -> [CameraKitPicture] {
        let folder = CameraKitStore.shared.cacheDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var result: [CameraKitPicture] = []
        for item in items {
            guard let id = UUID(uuidString: item.id) else { continue }
            let file = folder.appendingPathComponent(CameraKitUploadPlan.cacheName(for: item))
            if !FileManager.default.fileExists(atPath: file.path) {
                let path = "\(PhoneCameraKitRoute.file)?id=\(item.id)"
                guard let bytes = try? await client.getData(path: path) else { continue }
                try? bytes.write(to: file, options: .atomic)
            }
            result.append(CameraKitPicture(
                id: id,
                kind: item.kind,
                name: item.name,
                orientation: item.orientation == .vertical ? .portrait : .landscape,
                fileURL: file
            ))
        }
        return result
    }
}

// MARK: - CameraKitUploadPlan

/// Chunking and naming rules for kit transfers (pure, unit-tested).
struct CameraKitUploadPlan {
    let byteCount: Int
    let uploadId = UUID().uuidString

    /// Number of requests needed for the picture.
    var chunkCount: Int {
        max(1, (byteCount + PhoneCameraKitRoute.uploadChunkBytes - 1) / PhoneCameraKitRoute.uploadChunkBytes)
    }

    /// Byte range of one chunk.
    /// - Parameter index: Zero-based chunk index.
    /// - Returns: Range inside the picture data.
    func range(of index: Int) -> Range<Int> {
        let start = index * PhoneCameraKitRoute.uploadChunkBytes
        return start..<min(byteCount, start + PhoneCameraKitRoute.uploadChunkBytes)
    }

    /// Query items shared by every chunk.
    static func query(kind: PhoneCameraKitItem.Kind, name: String, fileExtension: String) -> String {
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "kind", value: kind.rawValue),
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "ext", value: fileExtension)
        ]
        return components.percentEncodedQuery ?? "kind=\(kind.rawValue)"
    }

    /// Cache file name; changes when the Mac picture changes.
    static func cacheName(for item: PhoneCameraKitItem) -> String {
        let safeVersion = item.version.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return "\(item.id)-\(safeVersion)"
    }
}
