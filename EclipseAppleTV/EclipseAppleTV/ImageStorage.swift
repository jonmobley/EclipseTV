//
//  ImageStorage.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import os.log

class ImageStorage {
    // MARK: - Singleton
    
    static let shared = ImageStorage()
    
    // MARK: - Properties
    
    private let fileManager = FileManager.default
    private let logger = Logger(subsystem: "com.eclipsetv.app", category: "ImageStorage")

    /// Location for user media. On tvOS, Caches is the reliable writable location and
    /// is durable in practice (only purged under genuine storage pressure). This was the
    /// app's original, working location; a later move to Application Support broke saving
    /// on tvOS. Note: for guaranteed persistence Apple's intended option is iCloud/CloudKit.
    private let mediaDirectory: URL
    
    // MARK: - Initialization
    
    private init() {
        let baseDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        mediaDirectory = baseDirectory.appendingPathComponent("Media", isDirectory: true)
        createImagesDirectory()
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

    /// Removes files in the media directory that the library no longer references —
    /// e.g. leftovers from an interrupted receive or a legacy code path. Compares by
    /// file name so a media-directory relocation doesn't orphan everything at once.
    ///
    /// This intentionally replaces the old "keep the N most recent files" sweep, which
    /// was never wired up and would have deleted files still in the library once it
    /// grew past the cap. Runs on a utility queue; safe to call at launch.
    func cleanupOrphanedFiles(keeping referencedPaths: [String]) {
        let imagesDir = getImagesDirectory()
        let referencedNames = Set(referencedPaths.map { ($0 as NSString).lastPathComponent })
        DispatchQueue.global(qos: .utility).async { [logger] in
            let fm = FileManager.default
            guard let files = try? fm.contentsOfDirectory(at: imagesDir,
                                                          includingPropertiesForKeys: nil) else { return }
            for fileURL in files where !referencedNames.contains(fileURL.lastPathComponent) {
                do {
                    try fm.removeItem(at: fileURL)
                    logger.info("Removed orphaned media file: \(fileURL.lastPathComponent, privacy: .public)")
                } catch {
                    logger.error("Failed to remove orphaned file: \(error.localizedDescription)")
                }
            }
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