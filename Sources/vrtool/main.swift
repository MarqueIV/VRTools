import Foundation
import VRTools

/// Simple CLI tool for converting VR180 images to side-by-side format
/// Usage: vrtool <input.jpg> [output.jpg]

func printUsage() {
    let executableName = (CommandLine.arguments.first as NSString?)?.lastPathComponent ?? "vrtool"
    print("""
        VR180 to Side-by-Side Converter

        Usage: \(executableName) <input.jpg> [output.jpg]

        Arguments:
          input.jpg   Path to a VR180 JPEG image (with embedded right eye in XMP metadata)
          output.jpg  Optional output path. If not specified, creates <input>-converted.jpg

        Examples:
          \(executableName) photo.jpg
          \(executableName) photo.jpg photo-sbs.jpg
        """)
}

func main() -> Int32 {
    let args = CommandLine.arguments

    // Check for help flag
    if args.contains("-h") || args.contains("--help") {
        printUsage()
        return 0
    }

    // Need at least the input file
    guard args.count >= 2 else {
        print("Error: No input file specified.\n")
        printUsage()
        return 1
    }

    let inputPath = args[1]
    let inputURL = URL(fileURLWithPath: inputPath)

    // Determine output URL
    let outputURL: URL
    if args.count >= 3 {
        outputURL = URL(fileURLWithPath: args[2])
    } else {
        // Generate default output name
        let directory = inputURL.deletingLastPathComponent()
        let filename = inputURL.deletingPathExtension().lastPathComponent
        let ext = inputURL.pathExtension.isEmpty ? "jpg" : inputURL.pathExtension
        outputURL = directory.appendingPathComponent("\(filename)-converted.\(ext)")
    }

    // Perform conversion
    let converter = VR180Converter()

    do {
        print("Converting \(inputURL.lastPathComponent)...")
        let result = try converter.convertToSideBySide(inputURL: inputURL)

        // If custom output path specified, move the file
        if args.count >= 3 && result != outputURL {
            try FileManager.default.moveItem(at: result, to: outputURL)
        }

        print("Success! Output saved to: \(outputURL.path)")
        return 0
    } catch let error as VR180Error {
        print("Error: \(error.localizedDescription)")
        return 1
    } catch {
        print("Error: \(error.localizedDescription)")
        return 1
    }
}

exit(main())
