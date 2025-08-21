import Foundation
import Combine

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
    @Published private(set) var currentIndex: Int = 0
    
    private let storageKey = "EclipseTV.recentImagesKey"
    
    private init() {
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
    
    func addMediaBatch(paths: [String]) {
        print("📦 [BATCH] Adding batch of \(paths.count) paths")
        
        // Filter out duplicates
        let newPaths = paths.filter { !mediaPaths.contains($0) }
        
        print("📦 [BATCH] After filtering duplicates: \(newPaths.count) new paths")
        
        guard !newPaths.isEmpty else { 
            print("📦 [BATCH] No new paths to add")
            return 
        }
        
        mediaPaths.append(contentsOf: newPaths)
        saveToStorage()
        
        print("📦 [BATCH] Added batch. Total paths now: \(mediaPaths.count)")
        
        // Call general change delegate - let UI do a full reload for batch operations
        delegate?.mediaDataDidChange()
    }
    
    func removeMedia(at index: Int) {
        guard index >= 0 && index < count else { return }
        
        mediaPaths.remove(at: index)
        
        // Adjust current index
        if currentIndex >= count {
            currentIndex = max(0, count - 1)
        } else if index <= currentIndex && currentIndex > 0 {
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
    
    // MARK: - Storage
    
    private func loadFromStorage() {
        if let saved = UserDefaults.standard.stringArray(forKey: storageKey) {
            // Filter out non-existent files
            mediaPaths = saved.filter { FileManager.default.fileExists(atPath: $0) }
            
            // Save cleaned list if we removed any
            if mediaPaths.count != saved.count {
                saveToStorage()
            }
        }
    }
    
    private func saveToStorage() {
        UserDefaults.standard.set(mediaPaths, forKey: storageKey)
    }
    
    // DEBUG HELPER (remove after testing)
    func debugPrint() {
        print("📊 DataSource State:")
        print("   Paths: \(mediaPaths)")
        print("   Current Index: \(currentIndex)")
        print("   Count: \(count)")
        print("   Current Path: \(getCurrentPath() ?? "nil")")
    }
} 