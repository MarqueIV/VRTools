import XCTest
@testable import VRTools
import Foundation
import CoreGraphics
import ImageIO

final class VR180ConverterTests: XCTestCase {

    var converter: VR180Converter!
    var testImageURL: URL!
    var tempDirectory: URL!

    override func setUpWithError() throws {
        converter = VR180Converter()

        // Create a temp directory for test outputs
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        // Get test image from bundle resources
        testImageURL = Bundle.module.url(forResource: "Slam_20260108_080029_086", withExtension: "jpg", subdirectory: "Resources")
    }

    override func tearDownWithError() throws {
        // Clean up temp directory
        if let tempDir = tempDirectory {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    // MARK: - Basic Functionality Tests

    func testConverterInitialization() {
        XCTAssertNotNil(converter)
    }

    func testConversionWithValidVR180Image() throws {
        guard let inputURL = testImageURL else {
            XCTFail("Test image not found in bundle resources")
            return
        }

        // Copy test image to temp directory
        let tempInputURL = tempDirectory.appendingPathComponent("test-input.jpg")
        try FileManager.default.copyItem(at: inputURL, to: tempInputURL)

        // Perform conversion
        let outputURL = try converter.convertToSideBySide(inputURL: tempInputURL)

        // Verify output file exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path), "Output file should exist")

        // Verify output filename has -converted suffix
        XCTAssertTrue(outputURL.lastPathComponent.contains("-converted"), "Output should have -converted suffix")

        // Verify output is a valid image
        let outputData = try Data(contentsOf: outputURL)
        guard let source = CGImageSourceCreateWithData(outputData as CFData, nil),
              let outputImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            XCTFail("Output should be a valid image")
            return
        }

        // Verify side-by-side format (width should be roughly double the height for VR180)
        // VR180 images are typically ~180 degrees horizontal, so SBS should be wider
        XCTAssertGreaterThan(outputImage.width, outputImage.height, "SBS image should be wider than tall")
    }

    func testOutputFilenameGeneration() throws {
        guard let inputURL = testImageURL else {
            XCTFail("Test image not found")
            return
        }

        // Copy to temp with known name
        let tempInputURL = tempDirectory.appendingPathComponent("my-photo.jpg")
        try FileManager.default.copyItem(at: inputURL, to: tempInputURL)

        let outputURL = try converter.convertToSideBySide(inputURL: tempInputURL)

        XCTAssertEqual(outputURL.lastPathComponent, "my-photo-converted.jpg")
    }

    func testOutputImageDimensions() throws {
        guard let inputURL = testImageURL else {
            XCTFail("Test image not found")
            return
        }

        let tempInputURL = tempDirectory.appendingPathComponent("test.jpg")
        try FileManager.default.copyItem(at: inputURL, to: tempInputURL)

        // Get input image dimensions
        let inputData = try Data(contentsOf: tempInputURL)
        guard let inputSource = CGImageSourceCreateWithData(inputData as CFData, nil),
              let inputImage = CGImageSourceCreateImageAtIndex(inputSource, 0, nil) else {
            XCTFail("Could not load input image")
            return
        }

        let inputWidth = inputImage.width
        let inputHeight = inputImage.height

        // Convert
        let outputURL = try converter.convertToSideBySide(inputURL: tempInputURL)

        // Get output dimensions
        let outputData = try Data(contentsOf: outputURL)
        guard let outputSource = CGImageSourceCreateWithData(outputData as CFData, nil),
              let outputImage = CGImageSourceCreateImageAtIndex(outputSource, 0, nil) else {
            XCTFail("Could not load output image")
            return
        }

        // Output width should be approximately 2x input width (left + right eye)
        // Allow some tolerance since eyes might have slightly different dimensions
        let expectedMinWidth = inputWidth * 2 - 100
        let expectedMaxWidth = inputWidth * 2 + 100

        XCTAssertGreaterThanOrEqual(outputImage.width, expectedMinWidth,
            "Output width should be at least \(expectedMinWidth)")
        XCTAssertLessThanOrEqual(outputImage.width, expectedMaxWidth,
            "Output width should be at most \(expectedMaxWidth)")

        // Height should be similar to input
        XCTAssertEqual(outputImage.height, inputHeight, accuracy: 100,
            "Output height should be similar to input height")
    }

    // MARK: - Error Handling Tests

    func testFileNotFoundError() {
        let nonExistentURL = URL(fileURLWithPath: "/nonexistent/path/image.jpg")

        XCTAssertThrowsError(try converter.convertToSideBySide(inputURL: nonExistentURL)) { error in
            guard let vrError = error as? VR180Error else {
                XCTFail("Expected VR180Error")
                return
            }

            if case .fileNotFound = vrError {
                // Expected
            } else {
                XCTFail("Expected fileNotFound error, got \(vrError)")
            }
        }
    }

    func testInvalidImageError() throws {
        // Create a file with invalid image data
        let invalidImageURL = tempDirectory.appendingPathComponent("invalid.jpg")
        try "not an image".write(to: invalidImageURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try converter.convertToSideBySide(inputURL: invalidImageURL)) { error in
            // Should throw some error (could be various types depending on where it fails)
            XCTAssertNotNil(error)
        }
    }

    // MARK: - Performance Tests

    func testConversionPerformance() throws {
        guard let inputURL = testImageURL else {
            XCTFail("Test image not found")
            return
        }

        let tempInputURL = tempDirectory.appendingPathComponent("perf-test.jpg")
        try FileManager.default.copyItem(at: inputURL, to: tempInputURL)

        measure {
            do {
                let outputURL = try converter.convertToSideBySide(inputURL: tempInputURL)
                // Clean up for next iteration
                try? FileManager.default.removeItem(at: outputURL)
            } catch {
                XCTFail("Conversion failed: \(error)")
            }
        }
    }
}

// Helper extension for comparing with tolerance
extension XCTestCase {
    func XCTAssertEqual(_ value: Int, _ expected: Int, accuracy: Int, _ message: String = "") {
        XCTAssertTrue(abs(value - expected) <= accuracy, "\(message) - got \(value), expected \(expected) ± \(accuracy)")
    }
}
