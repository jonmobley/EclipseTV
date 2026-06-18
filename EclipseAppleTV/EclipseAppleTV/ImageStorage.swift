import Foundation
import os.log

class ImageStorage {
    // MARK: - Singleton
    
    static let shared = ImageStorage()
    
    // MARK: - Properties
    
    private let fileManager = FileManager.default
    private let logger = Logger(subsystem: "com.eclipsetv.app", category: "ImageStorage")

    /// Persistent location for user media. Lives in Application Support (which the OS
    /// does NOT purge) rather than Caches, so received media survives storage pressure.
    private let mediaDirectory: URL

    /// Previous (purgeable) location. Used only to migrate existing media on first launch
    /// after the storage relocation.
    private let legacyMediaDirectory: URL
    
    // MARK: - Initialization
    
    private init() {
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        mediaDirectory = baseDirectory.appendingPathComponent("Media", isDirectory: true)
        legacyMediaDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Media", isDirectory: true)
        
        // Create the media directory if it doesn't exist, then migrate any legacy files
        createImagesDirectory()
        migrateLegacyMediaIfNeeded()
    }
    
    // MARK: - Directory Management
    
    func getImagesDirectory() -> URL {
        return mediaDirectory
    }
    
    @discardableResult
    func createImagesDirectory() -> Bool {
        let imagesDirURL = getImagesDirectory()
        do {
            try fileManager.createDirectory(at: imagesDirURL, 
                                          withIntermediateDirectories: true, 
                                          attributes: nil)
            logger.info("Created directory: \(imagesDirURL.path)")
            return true
        } catch {
            logger.error("Error creating directory: \(error.localizedDescription)")
            return false
        }
    }

    /// One-time migration of media files from the old purgeable Caches location to the
    /// persistent Application Support location. Safe to call on every launch; it no-ops
    /// once the legacy directory is empty/absent.
    private func migrateLegacyMediaIfNeeded() {
        guard fileManager.fileExists(atPath: legacyMediaDirectory.path) else { return }

        do {
            let legacyFiles = try fileManager.contentsOfDirectory(at: legacyMediaDirectory,
                                                                  includingPropertiesForKeys: nil)
            for fileURL in legacyFiles {
                let destinationURL = mediaDirectory.appendingPathComponent(fileURL.lastPathComponent)
                if fileManager.fileExists(atPath: destinationURL.path) {
                    // Already migrated; remove the stale legacy copy
                    try? fileManager.removeItem(at: fileURL)
                    continue
                }
                do {
                    try fileManager.moveItem(at: fileURL, to: destinationURL)
                    logger.info("Migrated media file to persistent storage: \(fileURL.lastPathComponent)")
                } catch {
                    logger.error("Failed to migrate \(fileURL.lastPathComponent): \(error.localizedDescription)")
                }
            }
            // Remove the now-empty legacy directory
            try? fileManager.removeItem(at: legacyMediaDirectory)
        } catch {
            logger.error("Legacy media migration error: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Image Management
    
    func saveReceivedImage(_ imageData: Data) -> URL? {
        // Ensure directory exists
        if !createImagesDirectory() {
            return nil
        }
        
        let filename = "\(UUID().uuidString).jpg"
        let fileURL = getImagesDirectory().appendingPathComponent(filename)
        
        // Write on background thread as recommended
        do {
            try imageData.write(to: fileURL, options: [.atomic])
            logger.info("Saved image to: \(fileURL.path)")
            return fileURL
        } catch {
            logger.error("Error saving image: \(error.localizedDescription)")
            return nil
        }
    }
    
    func saveSampleImage(_ imageData: Data, name: String) -> URL? {
        // Ensure directory exists
        if !createImagesDirectory() {
            return nil
        }
        
        let filename = "sample_\(name).jpg"
        let fileURL = getImagesDirectory().appendingPathComponent(filename)
        
        // Only write if file doesn't exist
        if !fileManager.fileExists(atPath: fileURL.path) {
            do {
                try imageData.write(to: fileURL, options: [.atomic])
                logger.info("Saved sample image to: \(fileURL.path)")
                return fileURL
            } catch {
                logger.error("Error saving sample image: \(error.localizedDescription)")
                return nil
            }
        }
        
        return fileURL
    }
    
    // MARK: - Video Management
    
    func saveReceivedVideo(_ videoData: Data) -> URL? {
        // Ensure directory exists
        if !createImagesDirectory() {
            return nil
        }
        
        let filename = "\(UUID().uuidString).mp4"
        let fileURL = getImagesDirectory().appendingPathComponent(filename)
        
        // Write on background thread as recommended
        do {
            try videoData.write(to: fileURL, options: [.atomic])
            logger.info("Saved video to: \(fileURL.path)")
            return fileURL
        } catch {
            logger.error("Error saving video: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Cleanup
    
    func cleanupOldImages(keepMostRecent count: Int = 100) {
        let imagesDir = getImagesDirectory()
        do {
            let files = try fileManager.contentsOfDirectory(at: imagesDir, 
                                                          includingPropertiesForKeys: [.creationDateKey])
            let sortedFiles = try files.sorted { file1, file2 in
                let date1 = try file1.resourceValues(forKeys: [.creationDateKey]).creationDate!
                let date2 = try file2.resourceValues(forKeys: [.creationDateKey]).creationDate!
                return date1 > date2
            }
            
            // Delete files beyond the keep limit
            for fileURL in sortedFiles.dropFirst(count) {
                try fileManager.removeItem(at: fileURL)
                logger.info("Removed old image: \(fileURL.lastPathComponent)")
            }
        } catch {
            logger.error("Cleanup error: \(error.localizedDescription)")
        }
    }
    
    // MARK: - File Operations
    
    func fileExists(at path: String) -> Bool {
        return fileManager.fileExists(atPath: path)
    }
    
    func getDirectoryContents() -> [URL]? {
        let imagesDir = getImagesDirectory()
        do {
            return try fileManager.contentsOfDirectory(at: imagesDir, 
                                                     includingPropertiesForKeys: [.creationDateKey])
        } catch {
            logger.error("Error getting directory contents: \(error.localizedDescription)")
            return nil
        }
    }
    
    func removeFile(at url: URL) -> Bool {
        do {
            try fileManager.removeItem(at: url)
            logger.info("Removed file: \(url.lastPathComponent)")
            return true
        } catch {
            logger.error("Error removing file: \(error.localizedDescription)")
            return false
        }
    }
} 