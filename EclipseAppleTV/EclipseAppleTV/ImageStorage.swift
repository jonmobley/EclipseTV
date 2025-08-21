import Foundation
import os.log

class ImageStorage {
    // MARK: - Singleton
    
    static let shared = ImageStorage()
    
    // MARK: - Properties
    
    private let fileManager = FileManager.default
    private let logger = Logger(subsystem: "com.eclipsetv.app", category: "ImageStorage")
    private let imagesDirectory: URL
    
    // MARK: - Initialization
    
    private init() {
        // Get the documents directory
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        imagesDirectory = documentsDirectory.appendingPathComponent("Images")
        
        // Create the images directory if it doesn't exist
        createImagesDirectory()
    }
    
    // MARK: - Directory Management
    
    func getImagesDirectory() -> URL {
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("Media")
    }
    
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