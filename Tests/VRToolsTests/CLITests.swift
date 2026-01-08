import XCTest
import Foundation

final class CLITests: XCTestCase {

    var tempDirectory: URL!
    var testImageURL: URL!
    var vrtoolPath: URL!

    override func setUpWithError() throws {
        // Create temp directory for test outputs
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        // Get test image from bundle resources
        testImageURL = Bundle.module.url(forResource: "Slam_20260108_080029_086", withExtension: "jpg", subdirectory: "Resources")

        // Get path to built vrtool executable
        // In Swift Package tests, the executable should be in the build directory
        vrtoolPath = productsDirectory.appendingPathComponent("vrtool")
    }

    override func tearDownWithError() throws {
        // Clean up temp directory
        if let tempDir = tempDirectory {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    /// Returns path to the built products directory
    var productsDirectory: URL {
        #if os(macOS)
        for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
            return bundle.bundleURL.deletingLastPathComponent()
        }
        fatalError("couldn't find the products directory")
        #else
        return Bundle.main.bundleURL
        #endif
    }

    // MARK: - CLI Tests

    func testCLIHelp() throws {
        let process = Process()
        process.executableURL = vrtoolPath
        process.arguments = ["--help"]

        let pipe = Pipe()
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        XCTAssertEqual(process.terminationStatus, 0, "Help should exit with status 0")
        XCTAssertTrue(output.contains("Usage:"), "Help output should contain usage info")
        XCTAssertTrue(output.contains("vrtool"), "Help output should mention vrtool")
    }

    func testCLINoArguments() throws {
        let process = Process()
        process.executableURL = vrtoolPath
        process.arguments = []

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        XCTAssertNotEqual(process.terminationStatus, 0, "No arguments should exit with error")
    }

    func testCLIWithValidImage() throws {
        guard let inputURL = testImageURL else {
            XCTFail("Test image not found")
            return
        }

        // Copy test image to temp directory
        let tempInputURL = tempDirectory.appendingPathComponent("cli-test.jpg")
        try FileManager.default.copyItem(at: inputURL, to: tempInputURL)

        let process = Process()
        process.executableURL = vrtoolPath
        process.arguments = [tempInputURL.path]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""

        XCTAssertEqual(process.terminationStatus, 0, "Conversion should succeed. Output: \(output)")

        // Check output file was created
        let expectedOutputURL = tempDirectory.appendingPathComponent("cli-test-converted.jpg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedOutputURL.path),
            "Output file should exist at \(expectedOutputURL.path)")
    }

    func testCLIWithCustomOutputPath() throws {
        guard let inputURL = testImageURL else {
            XCTFail("Test image not found")
            return
        }

        let tempInputURL = tempDirectory.appendingPathComponent("input.jpg")
        try FileManager.default.copyItem(at: inputURL, to: tempInputURL)

        let customOutputURL = tempDirectory.appendingPathComponent("custom-output.jpg")

        let process = Process()
        process.executableURL = vrtoolPath
        process.arguments = [tempInputURL.path, customOutputURL.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0, "Conversion should succeed")
        XCTAssertTrue(FileManager.default.fileExists(atPath: customOutputURL.path),
            "Custom output file should exist")
    }

    func testCLIWithNonExistentFile() throws {
        let process = Process()
        process.executableURL = vrtoolPath
        process.arguments = ["/nonexistent/path/image.jpg"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        XCTAssertNotEqual(process.terminationStatus, 0, "Should exit with error for non-existent file")

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        XCTAssertTrue(output.lowercased().contains("error") || output.lowercased().contains("not found"),
            "Output should indicate an error")
    }

    func testCLIOutputContainsSuccessMessage() throws {
        guard let inputURL = testImageURL else {
            XCTFail("Test image not found")
            return
        }

        let tempInputURL = tempDirectory.appendingPathComponent("success-test.jpg")
        try FileManager.default.copyItem(at: inputURL, to: tempInputURL)

        let process = Process()
        process.executableURL = vrtoolPath
        process.arguments = [tempInputURL.path]

        let pipe = Pipe()
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        XCTAssertTrue(output.contains("Success") || output.contains("success"),
            "Output should indicate success")
        XCTAssertTrue(output.contains("-converted"),
            "Output should mention the converted filename")
    }
}
