//
//  MediaDataSource.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Combine
import os.log

protocol MediaDataSourceDelegate: AnyObject {
    func mediaDataDidChange()
    func mediaData(_ dataSource: MediaDataSource, didAddItemAt index: Int)
    func mediaData(_ dataSource: MediaDataSource, didRemoveItemAt index: Int)
    func mediaData(_ dataSource: MediaDataSource, didMoveItemFrom sourceIndex: Int, to targetIndex: Int)
}

class MediaDataSource: ObservableObject {
    static let shared = MediaDataSource()

    typealias LibraryMode = EclipseShareProtocol.LibraryMode

    weak var delegate: MediaDataSourceDelegate?

    // SINGLE SOURCE OF TRUTH for the *active* library bucket
    @Published private(set) var mediaPaths: [String] = []
    @Published private(set) var currentIndex: Int = 0 {
        didSet {
            guard currentIndex != oldValue else { return }
            defaults.set(currentIndex, forKey: indexKey(for: activeLibraryMode))
        }
    }
    @Published private(set) var activeLibraryMode: LibraryMode = .landscape

    private let legacyStorageKey = "EclipseTV.recentImagesKey"
    private let legacyIndexKey = "EclipseTV.currentIndexKey"
    private let legacyLedgerKey = "EclipseTV.unavailableLedger"
    private let activeModeKey = "EclipseTV.activeLibraryMode"
    private let logger = Logger(subsystem: "com.eclipsetv.app", category: "MediaDataSource")

    private let defaults: UserDefaults

    /// Per-mode unavailable ledgers. Active ledger exposed via `unavailableLedger`.
    private var ledgers: [LibraryMode: UnavailableLedger] = [:]

    /// Offline (non-active) path lists kept in memory so inbound commands can target them.
    private var offlinePaths: [LibraryMode: [String]] = [:]
    private var offlineIndex: [LibraryMode: Int] = [:]

    /// Records library items whose files were purged by tvOS so the companion can show
    /// them as unavailable and offer to re-send.
    var unavailableLedger: UnavailableLedger {
        ledgers[activeLibraryMode]!
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        for mode in LibraryMode.allCases {
            ledgers[mode] = UnavailableLedger(
                defaults: defaults,
                storageKey: "\(legacyLedgerKey).\(mode.rawValue)"
            )
        }
        migrateLegacyKeysIfNeeded()
        if let raw = defaults.string(forKey: activeModeKey),
           let mode = LibraryMode(rawValue: raw) {
            activeLibraryMode = mode
        }
        loadAllBuckets()
        publishActiveBucket()
    }

    // MARK: - Mode Switching

    /// Switches the active Landscape / Vertical library. Reloads published state and
    /// notifies the UI delegate.
    func setActiveLibraryMode(_ mode: LibraryMode) {
        guard mode != activeLibraryMode else { return }
        persistActiveBucket()
        activeLibraryMode = mode
        defaults.set(mode.rawValue, forKey: activeModeKey)
        publishActiveBucket()
        delegate?.mediaDataDidChange()
        logger.info("Active library mode -> \(mode.rawValue, privacy: .public)")
    }

    /// All file paths across both libraries (for orphan cleanup).
    func allReferencedPaths() -> [String] {
        var paths = mediaPaths
        for mode in LibraryMode.allCases where mode != activeLibraryMode {
            paths.append(contentsOf: offlinePaths[mode] ?? [])
        }
        return paths
    }

    // MARK: - Public Interface

    var count: Int { mediaPaths.count }
    var isEmpty: Bool { mediaPaths.isEmpty }
    var hasValidIndex: Bool { currentIndex >= 0 && currentIndex < count }

    func getCurrentPath() -> String? {
        guard hasValidIndex else { return nil }
        return mediaPaths[currentIndex]
    }

    func getPath(at index: Int) -> String? {
        guard index >= 0 && index < count else { return nil }
        return mediaPaths[index]
    }

    func setCurrentIndex(_ index: Int) {
        guard index >= 0 && index < count else { return }
        currentIndex = index
    }

    // MARK: - Mutations (All go through here)

    func addMedia(at path: String) {
        if mediaPaths.contains(path) { return }

        mediaPaths.append(path)
        persistActiveBucket()
        delegate?.mediaData(self, didAddItemAt: mediaPaths.count - 1)
        delegate?.mediaDataDidChange()
    }

    /// Appends media without changing `currentIndex` or nudging grid selection/focus.
    @discardableResult
    func addMediaSilently(at path: String) -> Bool {
        if mediaPaths.contains(path) { return false }

        mediaPaths.append(path)
        persistActiveBucket()
        delegate?.mediaDataDidChange()
        return true
    }

    /// Appends into a specific mode bucket (used when restoring / receiving for a mode).
    @discardableResult
    func addMediaSilently(at path: String, mode: LibraryMode) -> Bool {
        if mode == activeLibraryMode {
            return addMediaSilently(at: path)
        }
        var paths = offlinePaths[mode] ?? []
        if paths.contains(path) { return false }
        paths.append(path)
        offlinePaths[mode] = paths
        defaults.set(paths, forKey: storageKey(for: mode))
        return true
    }

    func addMediaBatch(paths: [String]) {
        var seen = Set(mediaPaths)
        var newPaths: [String] = []
        for path in paths where seen.insert(path).inserted {
            newPaths.append(path)
        }

        guard !newPaths.isEmpty else {
            logger.debug("addMediaBatch: no new paths to add")
            return
        }

        mediaPaths.append(contentsOf: newPaths)
        persistActiveBucket()

        logger.debug("addMediaBatch: added \(newPaths.count) paths, total now \(self.mediaPaths.count)")

        delegate?.mediaDataDidChange()
    }

    func removeMedia(at index: Int) {
        guard index >= 0 && index < count else { return }

        let removedPath = mediaPaths[index]
        mediaPaths.remove(at: index)

        let mediaRoot = ImageStorage.shared.getMediaRootDirectory().path
        if removedPath.hasPrefix(mediaRoot) {
            _ = ImageStorage.shared.removeFile(at: URL(fileURLWithPath: removedPath))
        }

        if MediaItem(path: removedPath).isVideo {
            VideoThumbnailCache.shared.removeThumbnail(for: removedPath)
        }

        if currentIndex >= count {
            currentIndex = max(0, count - 1)
        } else if index <= currentIndex && currentIndex > 0 {
            currentIndex -= 1
        }

        persistActiveBucket()
        delegate?.mediaData(self, didRemoveItemAt: index)
        delegate?.mediaDataDidChange()
    }

    /// Removes an item by file-name id in the given mode (or active if nil).
    func removeMedia(id: String, mode: LibraryMode? = nil) {
        let target = mode ?? activeLibraryMode
        if target == activeLibraryMode {
            if let index = mediaPaths.firstIndex(where: {
                URL(fileURLWithPath: $0).lastPathComponent == id
            }) {
                removeMedia(at: index)
            }
            return
        }
        var paths = offlinePaths[target] ?? []
        guard let index = paths.firstIndex(where: {
            URL(fileURLWithPath: $0).lastPathComponent == id
        }) else { return }
        let removedPath = paths.remove(at: index)
        offlinePaths[target] = paths
        defaults.set(paths, forKey: storageKey(for: target))
        let mediaRoot = ImageStorage.shared.getMediaRootDirectory().path
        if removedPath.hasPrefix(mediaRoot) {
            _ = ImageStorage.shared.removeFile(at: URL(fileURLWithPath: removedPath))
        }
        var idx = offlineIndex[target] ?? 0
        if idx >= paths.count { idx = max(0, paths.count - 1) }
        else if index <= idx && idx > 0 { idx -= 1 }
        offlineIndex[target] = idx
        defaults.set(idx, forKey: indexKey(for: target))
    }

    func moveMedia(from sourceIndex: Int, to targetIndex: Int) {
        guard sourceIndex != targetIndex,
              sourceIndex >= 0 && sourceIndex < count,
              targetIndex >= 0 && targetIndex < count else { return }

        let item = mediaPaths.remove(at: sourceIndex)
        mediaPaths.insert(item, at: targetIndex)

        if currentIndex == sourceIndex {
            currentIndex = targetIndex
        } else if sourceIndex < currentIndex && targetIndex >= currentIndex {
            currentIndex -= 1
        } else if sourceIndex > currentIndex && targetIndex <= currentIndex {
            currentIndex += 1
        }

        persistActiveBucket()
        delegate?.mediaData(self, didMoveItemFrom: sourceIndex, to: targetIndex)
        delegate?.mediaDataDidChange()
    }

    /// Reorders the live list so item file names match `orderedIds`.
    func applyOrder(orderedIds: [String], mode: LibraryMode? = nil) {
        let target = mode ?? activeLibraryMode
        if target == activeLibraryMode {
            applyOrderActive(orderedIds: orderedIds)
            return
        }
        var paths = offlinePaths[target] ?? []
        guard !orderedIds.isEmpty, !paths.isEmpty else { return }
        let currentPath: String? = {
            let idx = offlineIndex[target] ?? 0
            return (idx >= 0 && idx < paths.count) ? paths[idx] : nil
        }()
        var pathByName: [String: String] = [:]
        for path in paths {
            pathByName[URL(fileURLWithPath: path).lastPathComponent] = path
        }
        var reordered: [String] = []
        var used = Set<String>()
        for id in orderedIds {
            if let path = pathByName[id], !used.contains(path) {
                reordered.append(path)
                used.insert(path)
            }
        }
        for path in paths where !used.contains(path) {
            reordered.append(path)
        }
        guard reordered != paths else { return }
        offlinePaths[target] = reordered
        defaults.set(reordered, forKey: storageKey(for: target))
        if let currentPath, let newIndex = reordered.firstIndex(of: currentPath) {
            offlineIndex[target] = newIndex
            defaults.set(newIndex, forKey: indexKey(for: target))
        }
    }

    private func applyOrderActive(orderedIds: [String]) {
        guard !orderedIds.isEmpty, count > 0 else { return }

        let currentPath = getCurrentPath()
        var pathByName: [String: String] = [:]
        for path in mediaPaths {
            pathByName[URL(fileURLWithPath: path).lastPathComponent] = path
        }

        var reordered: [String] = []
        var used = Set<String>()
        for id in orderedIds {
            if let path = pathByName[id], !used.contains(path) {
                reordered.append(path)
                used.insert(path)
            }
        }
        for path in mediaPaths where !used.contains(path) {
            reordered.append(path)
        }

        guard reordered != mediaPaths else { return }
        mediaPaths = reordered

        if let currentPath = currentPath, let newIndex = reordered.firstIndex(of: currentPath) {
            currentIndex = newIndex
        }

        persistActiveBucket()
        delegate?.mediaDataDidChange()
    }

    func nextIndex() -> Bool {
        guard currentIndex < count - 1 else { return false }
        currentIndex += 1
        return true
    }

    func previousIndex() -> Bool {
        guard currentIndex > 0 else { return false }
        currentIndex -= 1
        return true
    }

    /// Selects the live item by file-name id within a mode (activates that mode first
    /// when it differs so UI/sync stay aligned).
    @discardableResult
    func selectItem(id: String, mode: LibraryMode? = nil) -> Bool {
        let target = mode ?? activeLibraryMode
        if target != activeLibraryMode {
            setActiveLibraryMode(target)
        }
        guard let index = mediaPaths.firstIndex(where: {
            URL(fileURLWithPath: $0).lastPathComponent == id
        }) else { return false }
        setCurrentIndex(index)
        return true
    }

    // MARK: - Availability

    func revalidateAvailability() {
        guard count > 0 else { return }
        for index in stride(from: count - 1, through: 0, by: -1) {
            let path = mediaPaths[index]
            if !FileManager.default.fileExists(atPath: path) {
                recordUnavailable(path: path, lastIndex: index, mode: activeLibraryMode)
                removeMedia(at: index)
            }
        }
    }

    private func recordUnavailable(path: String, lastIndex: Int, mode: LibraryMode) {
        let item = MediaItem(path: path)
        ledgers[mode]?.record(id: item.fileName,
                              name: item.fileName,
                              isVideo: item.isVideo,
                              lastIndex: lastIndex)
    }

    func ledger(for mode: LibraryMode) -> UnavailableLedger {
        ledgers[mode]!
    }

    // MARK: - Storage

    private func storageKey(for mode: LibraryMode) -> String {
        "\(legacyStorageKey).\(mode.rawValue)"
    }

    private func indexKey(for mode: LibraryMode) -> String {
        "\(legacyIndexKey).\(mode.rawValue)"
    }

    private func migrateLegacyKeysIfNeeded() {
        let landscapePathsKey = storageKey(for: .landscape)
        if defaults.stringArray(forKey: landscapePathsKey) == nil,
           let legacy = defaults.stringArray(forKey: legacyStorageKey) {
            defaults.set(legacy, forKey: landscapePathsKey)
            defaults.removeObject(forKey: legacyStorageKey)
            logger.info("Migrated library paths → landscape (\(legacy.count) items)")
        }
        if defaults.object(forKey: indexKey(for: .landscape)) == nil,
           defaults.object(forKey: legacyIndexKey) != nil {
            defaults.set(defaults.integer(forKey: legacyIndexKey), forKey: indexKey(for: .landscape))
            defaults.removeObject(forKey: legacyIndexKey)
        }
        let landscapeLedgerKey = "\(legacyLedgerKey).\(LibraryMode.landscape.rawValue)"
        if defaults.data(forKey: landscapeLedgerKey) == nil,
           let legacyData = defaults.data(forKey: legacyLedgerKey) {
            defaults.set(legacyData, forKey: landscapeLedgerKey)
            defaults.removeObject(forKey: legacyLedgerKey)
            ledgers[.landscape] = UnavailableLedger(
                defaults: defaults,
                storageKey: landscapeLedgerKey
            )
        }
    }

    private func loadAllBuckets() {
        for mode in LibraryMode.allCases {
            let paths = resolvePaths(
                saved: defaults.stringArray(forKey: storageKey(for: mode)) ?? [],
                mode: mode
            )
            let savedIndex = defaults.integer(forKey: indexKey(for: mode))
            let index = (savedIndex >= 0 && savedIndex < paths.count) ? savedIndex : 0
            if mode == activeLibraryMode {
                // Published in publishActiveBucket
                offlinePaths[mode] = paths
                offlineIndex[mode] = index
            } else {
                offlinePaths[mode] = paths
                offlineIndex[mode] = index
            }
            defaults.set(paths, forKey: storageKey(for: mode))
            defaults.set(index, forKey: indexKey(for: mode))
        }
    }

    private func publishActiveBucket() {
        mediaPaths = offlinePaths[activeLibraryMode] ?? []
        let idx = offlineIndex[activeLibraryMode] ?? 0
        currentIndex = (idx >= 0 && idx < mediaPaths.count) ? idx : 0
    }

    private func persistActiveBucket() {
        offlinePaths[activeLibraryMode] = mediaPaths
        offlineIndex[activeLibraryMode] = currentIndex
        defaults.set(mediaPaths, forKey: storageKey(for: activeLibraryMode))
        defaults.set(currentIndex, forKey: indexKey(for: activeLibraryMode))
    }

    private func resolvePaths(saved: [String], mode: LibraryMode) -> [String] {
        let mediaDirectory = ImageStorage.shared.getImagesDirectory(for: mode)
        var resolved: [String] = []
        for (index, path) in saved.enumerated() {
            if FileManager.default.fileExists(atPath: path) {
                resolved.append(path)
            } else {
                let candidate = mediaDirectory
                    .appendingPathComponent((path as NSString).lastPathComponent).path
                if FileManager.default.fileExists(atPath: candidate) {
                    resolved.append(candidate)
                } else {
                    // Also try legacy flat Media/ then Landscape (migration edge).
                    let legacy = ImageStorage.shared.getMediaRootDirectory()
                        .appendingPathComponent((path as NSString).lastPathComponent).path
                    if FileManager.default.fileExists(atPath: legacy) {
                        resolved.append(legacy)
                    } else {
                        recordUnavailable(path: path, lastIndex: index, mode: mode)
                    }
                }
            }
        }
        return resolved
    }

    private func saveToStorage() {
        persistActiveBucket()
    }

    func debugState() {
        logger.debug(
            "DataSource state: mode=\(self.activeLibraryMode.rawValue, privacy: .public) count=\(self.count), currentIndex=\(self.currentIndex), currentPath=\(self.getCurrentPath() ?? "nil", privacy: .public)"
        )
    }
}
