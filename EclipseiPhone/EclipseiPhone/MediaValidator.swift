import UIKit
import AVFoundation

enum MediaValidationResult {
    case valid
    case invalid(reason: String)
}

class MediaValidator {
    
    static func validateVideo(at url: URL) async -> MediaValidationResult {
        let asset = AVURLAsset(url: url)
        
        do {
            let duration = try await asset.load(.duration).seconds
            
            if duration > 120 * 60 {
                let minutes = Int(duration / 60)
                return .invalid(reason: "Video too long (\(minutes) minutes). Maximum allowed is 2 hours.")
            }

            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = videoTracks.first else {
                return .invalid(reason: "Invalid video file or unsupported format")
            }

            let naturalSize = try await track.load(.naturalSize)
            let preferredTransform = try await track.load(.preferredTransform)
            
            let size = naturalSize.applying(preferredTransform)
            let width = abs(size.width)
            let height = abs(size.height)
            let maxDim = max(width, height)
            let minDim = min(width, height)

            if maxDim > 3840 {
                return .invalid(reason: "Video resolution too high (\(Int(maxDim))p). Maximum allowed is 4K (3840p).")
            }
            
            if minDim < 720 {
                return .invalid(reason: "Video resolution too low (\(Int(minDim))p). Minimum required is 720p.")
            }

            do {
                let fileAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
                if let fileSize = fileAttributes[.size] as? NSNumber,
                   fileSize.int64Value > 2_000_000_000 {
                    let fileSizeString = getFileSizeString(for: url) ?? "Unknown size"
                    return .invalid(reason: "File too large (\(fileSizeString)). Maximum allowed is 2GB.")
                }
            } catch {
                // If we can't get file size, proceed with validation
                // This prevents blocking valid videos due to file system errors
            }

            return .valid
            
        } catch {
            return .invalid(reason: "Unable to analyze video file: \(error.localizedDescription)")
        }
    }

    static func downscaleImage(_ image: UIImage, maxDimension: CGFloat = 3840) -> UIImage {
        let largestSide = max(image.size.width, image.size.height)
        guard largestSide > maxDimension else { return image }

        let scale = maxDimension / largestSide
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resizedImage = renderer.image { context in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        
        return resizedImage
    }
    
    static func imageNeedsDownscaling(_ image: UIImage, maxDimension: CGFloat = 3840) -> Bool {
        let largestSide = max(image.size.width, image.size.height)
        return largestSide > maxDimension
    }
    
    static func getDownscalingDescription(for image: UIImage, maxDimension: CGFloat = 3840) -> String? {
        guard imageNeedsDownscaling(image, maxDimension: maxDimension) else { return nil }
        
        let originalSize = max(image.size.width, image.size.height)
        let scale = maxDimension / originalSize
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        
        return "Image downscaled from \(Int(image.size.width))×\(Int(image.size.height)) to \(Int(newSize.width))×\(Int(newSize.height)) for optimal Apple TV compatibility."
    }
    
    static func getFileSizeString(for url: URL) -> String? {
        do {
            let fileAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let fileSize = fileAttributes[.size] as? NSNumber {
                let formatter = ByteCountFormatter()
                formatter.allowedUnits = [.useGB, .useMB]
                formatter.countStyle = .file
                return formatter.string(fromByteCount: fileSize.int64Value)
            }
        } catch {
            return nil
        }
        return nil
    }
}