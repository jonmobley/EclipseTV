//
//  MediaItem.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import UIKit
import AVFoundation

/// Represents a media file (image or video) in the library
struct MediaItem: Identifiable, Equatable, Codable {
    /// Identity is derived from the file path so two items referring to the same file are
    /// considered equal (and stable across encode/decode).
    var id: String { path }
    let path: String
    let type: MediaType
    let dateAdded: Date
    let fileSize: Int64
    
    static func == (lhs: MediaItem, rhs: MediaItem) -> Bool {
        return lhs.path == rhs.path
    }

    /// Video containers the TV plays. The one list every loader, validator, and
    /// cache consults, so an `.m4v` the validator accepted is never treated as a
    /// still by a thumbnail or bundle path.
    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]

    /// Still formats the TV decodes.
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic"]

    /// Whether `path` names a playable video by extension alone.
    static func isVideoPath(_ path: String) -> Bool {
        videoExtensions.contains(URL(fileURLWithPath: path).pathExtension.lowercased())
    }
    
    /// Full initializer with all parameters
    init(path: String, type: MediaType, dateAdded: Date, fileSize: Int64) {
        self.path = path
        self.type = type
        self.dateAdded = dateAdded
        self.fileSize = fileSize
    }
    
    /// Smart convenience initializer for quick UI operations
    /// Detects file type based on extension and provides default values
    init(path: String) {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()
        
        let type: MediaType
        if Self.videoExtensions.contains(ext) {
            type = .video(duration: 0)
        } else {
            // Default to JPEG for images, or determine from extension
            let format = MediaType.ImageFormat(extension: ext) ?? .jpeg
            type = .image(format: format)
        }
        
        self.path = path
        self.type = type
        self.dateAdded = Date()
        self.fileSize = 0
    }
    
    enum MediaType: Codable, Equatable {
        case image(format: ImageFormat)
        case video(duration: TimeInterval)
        
        enum ImageFormat: String, CaseIterable, Codable {
            case jpeg = "jpg"
            case png = "png" 
            case heic = "heic"

            /// Maps a file extension to a format, folding the `jpeg` spelling the
            /// validator accepts into `.jpeg`.
            init?(extension ext: String) {
                self.init(rawValue: ext == "jpeg" ? Self.jpeg.rawValue : ext)
            }
            
            var displayName: String {
                switch self {
                case .jpeg: return "JPEG"
                case .png: return "PNG"
                case .heic: return "HEIC"
                }
            }
        }
        
        var isVideo: Bool {
            if case .video = self { return true }
            return false
        }
        
        var displayName: String {
            switch self {
            case .image(let format):
                return format.displayName
            case .video(let duration):
                let minutes = Int(duration) / 60
                let seconds = Int(duration) % 60
                return "Video (\(minutes):\(String(format: "%02d", seconds)))"
            }
        }
    }
    
    /// Computed properties for convenience
    var isVideo: Bool { type.isVideo }
    var fileName: String { URL(fileURLWithPath: path).lastPathComponent }
    var fileExtension: String { URL(fileURLWithPath: path).pathExtension.lowercased() }
    
    /// Create MediaItem from file path
    static func from(path: String) async throws -> MediaItem {
        let url = URL(fileURLWithPath: path)
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        let fileSize = attributes[.size] as? Int64 ?? 0
        let dateAdded = attributes[.creationDate] as? Date ?? Date()
        
        let ext = url.pathExtension.lowercased()
        let type: MediaType
        
        if videoExtensions.contains(ext) {
            let duration = try await getVideoDuration(for: url)
            type = .video(duration: duration)
        } else if let format = MediaType.ImageFormat(extension: ext) {
            type = .image(format: format)
        } else {
            throw MediaError.unsupportedFormat(
                extension: ext,
                supportedFormats: imageExtensions.sorted() + videoExtensions.sorted()
            )
        }
        
        return MediaItem(path: path, type: type, dateAdded: dateAdded, fileSize: fileSize)
    }
    
    private static func getVideoDuration(for url: URL) async throws -> TimeInterval {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        return duration.seconds
    }
}

// MARK: - Extensions
extension MediaItem {
    /// Get file size in human readable format
    var fileSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
    
    /// Check if file exists on disk
    var fileExists: Bool {
        FileManager.default.fileExists(atPath: path)
    }
    
    /// Get creation date formatted
    var dateAddedFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: dateAdded)
    }
} 