// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VRTools",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "VRTools",
            targets: ["VRTools"]
        ),
        .executable(
            name: "vrtool",
            targets: ["vrtool"]
        )
    ],
    targets: [
        .target(
            name: "VRTools",
            dependencies: []
        ),
        .executableTarget(
            name: "vrtool",
            dependencies: ["VRTools"]
        ),
        .testTarget(
            name: "VRToolsTests",
            dependencies: ["VRTools"],
            resources: [
                .copy("Resources")
            ]
        )
    ]
)
