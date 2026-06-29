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
    
    weak var delegate: MediaDataSourceDelegate?
    
    // SINGLE SOURCE OF TRUTH
    @Published private(set) var mediaPaths: [String] = []
    @Published private(set) var currentIndex: Int = 0 {
        didSet {
            guard currentIndex != oldValue else { return }
            defaults.set(currentIndex, forKey: indexStorageKey)
        }
    }
    
    private let storageKey = "EclipseTV.recentImagesKey"
    private let indexStorageKey = "EclipseTV.currentIndexKey"
    private let logger = Logger(subsystem: "com.eclipsetv.app", category: "MediaDataSource")

    /// Backing store for persistence. Injectable so tests can use an isolated
    /// `UserDefaults` suite instead of polluting `.standard`.
    private let defaults: UserDefaults

    /// Records library items whose files were purged by tvOS so the companion can show
    /// them as unavailable and offer to re-send. Shares this instance's `defaults`.
    let unavailableLedger: UnavailableLedger

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.unavailableLedger = UnavailableLedger(defaults: defaults)
        loadFromStorage()
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
        // Don't add duplicates
        if mediaPaths.contains(path) { return }
        
        mediaPaths.append(path)
        saveToStorage()
        delegate?.mediaData(self, didAddItemAt: mediaPaths.count - 1)
        delegate?.mediaDataDidChange()
    }

    /// Appends media without changing `currentIndex` or nudging grid selection/focus.
    ///
    /// Used for passively received items (e.g. media sent from the companion) so an
    /// arrival never takes over the screen or steals the user's place. The `@Published`
    /// `mediaPaths` change still drives the manifest rebroadcast and a `mediaDataDidChange`
    /// reload (which preserves the existing selection); only the selecting/focusing
    /// `didAddItemAt` callback is intentionally skipped. Returns true if it was added.
    @discardableResult
    func addMediaSilently(at path: String) -> Bool {
        // Don't add duplicates
        if mediaPaths.contains(path) { return false }

        mediaPaths.append(path)
        saveToStorage()
        delegate?.mediaDataDidChange()
        return true
    }
    
    func addMediaBatch(paths: [String]) {
        // Filter out paths already present, and de-duplicate within the incoming
        // batch itself while preserving order.
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
        saveToStorage()
        
        logger.debug("addMediaBatch: added \(newPaths.count) paths, total now \(self.mediaPaths.count)")
        
        // Call general change delegate - let UI do a full reload for batch operations
        delegate?.mediaDataDidChange()
    }
    
    func removeMedia(at index: Int) {
        guard index >= 0 && index < count else { return }
        
        let removedPath = mediaPaths[index]
        mediaPaths.remove(at: index)

        // Delete the backing file (only for user media stored in our media directory;
        // bundle sample media is left untouched).
        let mediaDirectory = ImageStorage.shared.getImagesDirectory().path
        if removedPath.hasPrefix(mediaDirectory) {
            _ = ImageStorage.shared.removeFile(at: URL(fileURLWithPath: removedPath))
        }
        
        // Adjust current index
        if currentIndex >= count {
            // If current index is now beyond the array, set it to the last valid index
            currentIndex = max(0, count - 1)
        } else if index <= currentIndex && currentIndex > 0 {
            // If we deleted an item at or before the current index, shift current index back
            currentIndex -= 1
        }
        
        saveToStorage()
        delegate?.mediaData(self, didRemoveItemAt: index)
        delegate?.mediaDataDidChange()
    }
    
    func moveMedia(from sourceIndex: Int, to targetIndex: Int) {
        guard sourceIndex != targetIndex,
              sourceIndex >= 0 && sourceIndex < count,
              targetIndex >= 0 && targetIndex < count else { return }
        
        let item = mediaPaths.remove(at: sourceIndex)
        mediaPaths.insert(item, at: targetIndex)
        
        // Update current index if it was affected
        if currentIndex == sourceIndex {
            currentIndex = targetIndex
        } else if sourceIndex < currentIndex && targetIndex >= currentIndex {
            currentIndex -= 1
        } else if sourceIndex > currentIndex && targetIndex <= currentIndex {
            currentIndex += 1
        }
        
        saveToStorage()
        delegate?.mediaData(self, didMoveItemFrom: sourceIndex, to: targetIndex)
        delegate?.mediaDataDidChange()
    }
    
    /// Reorders the live list so item file names match `orderedIds`. Ids not present
    /// are ignored; any live paths not mentioned keep their relative order at the end.
    /// The currently live item stays live (its index is remapped). Triggers a single
    /// change notification + manifest broadcast when the order actually changes.
    func applyOrder(orderedIds: [String]) {
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
        // Preserve any live items the companion didn't mention (defensive).
        for path in mediaPaths where !used.contains(path) {
            reordered.append(path)
        }

        guard reordered != mediaPaths else { return }
        mediaPaths = reordered

        if let currentPath = currentPath, let newIndex = reordered.firstIndex(of: currentPath) {
            currentIndex = newIndex
        }

        saveToStorage()
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
    
    // MARK: - Availability

    /// Re-checks the live list and moves any now-missing files into the unavailable
    /// ledger (recording their current slot). Idempotent and safe to call repeatedly,
    /// e.g. on launch or when a companion connects. Walks back-to-front so index
    /// removals don't shift the positions still to be examined.
    func revalidateAvailability() {
        guard count > 0 else { return }
        for index in stride(from: count - 1, through: 0, by: -1) {
            let path = mediaPaths[index]
            if !FileManager.default.fileExists(atPath: path) {
                recordUnavailable(path: path, lastIndex: index)
                removeMedia(at: index)
            }
        }
    }

    /// Records a purged file in the ledger using its filename as the stable id.
    private func recordUnavailable(path: String, lastIndex: Int) {
        let item = MediaItem(path: path)
        unavailableLedger.record(id: item.fileName,
                                 name: item.fileName,
                                 isVideo: item.isVideo,
                                 lastIndex: lastIndex)
    }

    // MARK: - Storage
    
    private func loadFromStorage() {
        guard let saved = defaults.stringArray(forKey: storageKey) else { return }

        let mediaDirectory = ImageStorage.shared.getImagesDirectory()
        var resolved: [String] = []
        for (index, path) in saved.enumerated() {
            if FileManager.default.fileExists(atPath: path) {
                resolved.append(path)
            } else {
                // The media directory may have moved (e.g. Caches -> Application Support).
                // Re-resolve by filename against the current media directory.
                let candidate = mediaDirectory.appendingPathComponent((path as NSString).lastPathComponent).path
                if FileManager.default.fileExists(atPath: candidate) {
                    resolved.append(candidate)
                } else {
                    // File was purged (tvOS Caches eviction): remember it so the companion
                    // can show it as unavailable and offer to re-send. Keep it out of the
                    // live list so the TV grid stays clean.
                    recordUnavailable(path: path, lastIndex: index)
                }
            }
        }
        mediaPaths = resolved

        // Restore the last viewed index, clamped to the (possibly cleaned) list
        let savedIndex = defaults.integer(forKey: indexStorageKey)
        currentIndex = (savedIndex >= 0 && savedIndex < mediaPaths.count) ? savedIndex : 0

        // Persist the cleaned/remapped list if anything changed
        if resolved != saved {
            saveToStorage()
        }
    }
    
    private func saveToStorage() {
        defaults.set(mediaPaths, forKey: storageKey)
    }
    
    func debugState() {
        logger.debug("DataSource state: count=\(self.count), currentIndex=\(self.currentIndex), currentPath=\(self.getCurrentPath() ?? "nil", privacy: .public)")
    }
} 