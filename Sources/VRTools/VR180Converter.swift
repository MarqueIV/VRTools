import Foundation
import CoreGraphics
import ImageIO

#if canImport(AppKit)
import AppKit
#endif

/// Errors that can occur during VR180 conversion
public enum VR180Error: Error, LocalizedError {
    case fileNotFound(URL)
    case invalidImageData
    case noXMPMetadata
    case noRightEyeData
    case base64DecodingFailed
    case rightEyeImageDecodingFailed
    case leftEyeImageDecodingFailed
    case compositeCreationFailed
    case saveFailed(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "File not found: \(url.path)"
        case .invalidImageData:
            return "Invalid image data"
        case .noXMPMetadata:
            return "No XMP metadata found in image"
        case .noRightEyeData:
            return "No right eye image data (GImage:Data) found in XMP metadata"
        case .base64DecodingFailed:
            return "Failed to decode base64 right eye image data"
        case .rightEyeImageDecodingFailed:
            return "Failed to decode right eye image"
        case .leftEyeImageDecodingFailed:
            return "Failed to decode left eye (main) image"
        case .compositeCreationFailed:
            return "Failed to create side-by-side composite image"
        case .saveFailed(let reason):
            return "Failed to save image: \(reason)"
        }
    }
}

/// Converts VR180 photos (with embedded right eye in XMP metadata) to side-by-side format
public struct VR180Converter {

    public init() {}

    /// Converts a VR180 image to side-by-side format
    /// - Parameter inputURL: URL to the VR180 JPEG image
    /// - Returns: URL to the converted side-by-side image
    /// - Throws: VR180Error if conversion fails
    public func convertToSideBySide(inputURL: URL) throws -> URL {
        // Verify file exists
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw VR180Error.fileNotFound(inputURL)
        }

        // Read the file data
        let fileData = try Data(contentsOf: inputURL)

        // Extract XMP metadata and find the right eye image data
        let rightEyeBase64 = try extractRightEyeBase64(from: fileData)

        // Decode base64 to get right eye image data
        guard let rightEyeData = Data(base64Encoded: rightEyeBase64, options: .ignoreUnknownCharacters) else {
            throw VR180Error.base64DecodingFailed
        }

        // Load left eye (main image) as CGImage
        guard let leftEyeImage = loadCGImage(from: fileData) else {
            throw VR180Error.leftEyeImageDecodingFailed
        }

        // Load right eye as CGImage
        guard let rightEyeImage = loadCGImage(from: rightEyeData) else {
            throw VR180Error.rightEyeImageDecodingFailed
        }

        // Create side-by-side composite
        let compositeImage = try createSideBySideComposite(leftEye: leftEyeImage, rightEye: rightEyeImage)

        // Generate output URL
        let outputURL = generateOutputURL(from: inputURL)

        // Save the composite image
        try saveImage(compositeImage, to: outputURL)

        return outputURL
    }

    /// Extracts the base64-encoded right eye image data from XMP metadata
    private func extractRightEyeBase64(from data: Data) throws -> String {
        // First try to extract from standard XMP
        if let standardXMP = extractStandardXMP(from: data) {
            if let gImageData = extractGImageData(from: standardXMP) {
                return gImageData
            }
        }

        // Try extended XMP for large data
        if let extendedXMP = extractExtendedXMP(from: data) {
            if let gImageData = extractGImageData(from: extendedXMP) {
                return gImageData
            }
        }

        // Try combined approach - extended XMP might be split across segments
        let combinedXMP = extractAllXMPData(from: data)
        if let gImageData = extractGImageData(from: combinedXMP) {
            return gImageData
        }

        throw VR180Error.noRightEyeData
    }

    /// Extracts standard XMP data from JPEG APP1 segment
    private func extractStandardXMP(from data: Data) -> String? {
        let xmpMarker = "http://ns.adobe.com/xap/1.0/\0"
        guard let markerData = xmpMarker.data(using: .utf8) else { return nil }

        var index = 0
        while index < data.count - 4 {
            // Look for APP1 marker (0xFF 0xE1)
            if data[index] == 0xFF && data[index + 1] == 0xE1 {
                let segmentLength = Int(data[index + 2]) << 8 | Int(data[index + 3])
                let segmentStart = index + 4
                let segmentEnd = min(index + 2 + segmentLength, data.count)

                if segmentEnd > segmentStart {
                    let segmentData = data[segmentStart..<segmentEnd]

                    // Check if this is XMP data
                    if let range = segmentData.range(of: markerData) {
                        let xmpStart = range.upperBound
                        let xmpData = segmentData[xmpStart...]
                        if let xmpString = String(data: Data(xmpData), encoding: .utf8) {
                            return xmpString
                        }
                    }
                }

                index = segmentEnd
            } else {
                index += 1
            }
        }

        return nil
    }

    /// Extracts extended XMP data from JPEG APP1 segments
    private func extractExtendedXMP(from data: Data) -> String? {
        let extendedMarker = "http://ns.adobe.com/xmp/extension/\0"
        guard let markerData = extendedMarker.data(using: .utf8) else { return nil }

        var extendedChunks: [(offset: Int, data: Data)] = []

        var index = 0
        while index < data.count - 4 {
            // Look for APP1 marker (0xFF 0xE1)
            if data[index] == 0xFF && data[index + 1] == 0xE1 {
                let segmentLength = Int(data[index + 2]) << 8 | Int(data[index + 3])
                let segmentStart = index + 4
                let segmentEnd = min(index + 2 + segmentLength, data.count)

                if segmentEnd > segmentStart {
                    let segmentData = data[segmentStart..<segmentEnd]

                    // Check if this is extended XMP data
                    if let range = segmentData.range(of: markerData) {
                        // Extended XMP format: marker + GUID (32 bytes) + full length (4 bytes) + offset (4 bytes) + data
                        let headerStart = range.upperBound
                        if headerStart + 40 < segmentData.endIndex {
                            let offsetStart = headerStart + 36
                            let chunkOffset = Int(segmentData[offsetStart]) << 24 |
                                              Int(segmentData[offsetStart + 1]) << 16 |
                                              Int(segmentData[offsetStart + 2]) << 8 |
                                              Int(segmentData[offsetStart + 3])

                            let xmpStart = headerStart + 40
                            let xmpData = Data(segmentData[xmpStart...])
                            extendedChunks.append((offset: chunkOffset, data: xmpData))
                        }
                    }
                }

                index = segmentEnd
            } else {
                index += 1
            }
        }

        // Sort chunks by offset and combine
        if !extendedChunks.isEmpty {
            extendedChunks.sort { $0.offset < $1.offset }
            var combinedData = Data()
            for chunk in extendedChunks {
                combinedData.append(chunk.data)
            }
            return String(data: combinedData, encoding: .utf8)
        }

        return nil
    }

    /// Extracts all XMP data (both standard and extended) from the JPEG
    private func extractAllXMPData(from data: Data) -> String {
        var result = ""

        if let standard = extractStandardXMP(from: data) {
            result += standard
        }

        if let extended = extractExtendedXMP(from: data) {
            result += extended
        }

        return result
    }

    /// Extracts GImage:Data value from XMP string
    private func extractGImageData(from xmp: String) -> String? {
        // Try different patterns for GImage:Data
        let patterns = [
            // Attribute format: GImage:Data="..."
            #"GImage:Data="([^"]+)""#,
            // Element format: <GImage:Data>...</GImage:Data>
            #"<GImage:Data>([^<]+)</GImage:Data>"#,
            // With namespace prefix variations
            #"Data="([^"]+)"[^>]*xmlns[^>]*google[^>]*image"#,
            // Simple data extraction after GImage:Data
            #"GImage:Data[^>]*>([^<]+)<"#
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
               let match = regex.firstMatch(in: xmp, options: [], range: NSRange(xmp.startIndex..., in: xmp)),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: xmp) {
                let extracted = String(xmp[range])
                // Validate it looks like base64 (should be reasonably long and contain valid chars)
                if extracted.count > 1000 && extracted.range(of: #"^[A-Za-z0-9+/=\s]+$"#, options: .regularExpression) != nil {
                    // Clean up whitespace
                    return extracted.replacingOccurrences(of: "\\s", with: "", options: .regularExpression)
                }
            }
        }

        // Fallback: search for large base64 block after GImage:Data marker
        if let dataRange = xmp.range(of: "GImage:Data") {
            let afterMarker = xmp[dataRange.upperBound...]
            // Find the start of base64 data (after = or >)
            if let startRange = afterMarker.range(of: #"[=">]"#, options: .regularExpression) {
                let dataStart = afterMarker[startRange.upperBound...]
                // Extract until we hit a non-base64 character (excluding whitespace)
                var base64Chars = ""
                for char in dataStart {
                    if char.isLetter || char.isNumber || char == "+" || char == "/" || char == "=" {
                        base64Chars.append(char)
                    } else if char == "<" || char == "\"" {
                        break
                    }
                    // Skip whitespace
                }
                if base64Chars.count > 1000 {
                    return base64Chars
                }
            }
        }

        return nil
    }

    /// Loads a CGImage from raw data
    private func loadCGImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return image
    }

    /// Creates a side-by-side composite from left and right eye images
    private func createSideBySideComposite(leftEye: CGImage, rightEye: CGImage) throws -> CGImage {
        let leftWidth = leftEye.width
        let leftHeight = leftEye.height
        let rightWidth = rightEye.width
        let rightHeight = rightEye.height

        // Use the maximum height and sum of widths
        let compositeWidth = leftWidth + rightWidth
        let compositeHeight = max(leftHeight, rightHeight)

        // Create bitmap context
        let colorSpace = leftEye.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = leftEye.bitmapInfo.rawValue

        guard let context = CGContext(
            data: nil,
            width: compositeWidth,
            height: compositeHeight,
            bitsPerComponent: leftEye.bitsPerComponent,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw VR180Error.compositeCreationFailed
        }

        // Draw left eye on the left side
        let leftRect = CGRect(x: 0, y: (compositeHeight - leftHeight) / 2, width: leftWidth, height: leftHeight)
        context.draw(leftEye, in: leftRect)

        // Draw right eye on the right side
        let rightRect = CGRect(x: leftWidth, y: (compositeHeight - rightHeight) / 2, width: rightWidth, height: rightHeight)
        context.draw(rightEye, in: rightRect)

        guard let compositeImage = context.makeImage() else {
            throw VR180Error.compositeCreationFailed
        }

        return compositeImage
    }

    /// Generates the output URL with "-converted" suffix
    private func generateOutputURL(from inputURL: URL) -> URL {
        let directory = inputURL.deletingLastPathComponent()
        let filename = inputURL.deletingPathExtension().lastPathComponent
        let ext = inputURL.pathExtension

        let newFilename = "\(filename)-converted.\(ext)"
        return directory.appendingPathComponent(newFilename)
    }

    /// Saves a CGImage to a URL as JPEG
    private func saveImage(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil) else {
            throw VR180Error.saveFailed("Could not create image destination")
        }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.9
        ]

        CGImageDestinationAddImage(destination, image, options as CFDictionary)

        if !CGImageDestinationFinalize(destination) {
            throw VR180Error.saveFailed("Could not finalize image")
        }
    }
}
