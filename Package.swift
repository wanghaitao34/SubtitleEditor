// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SubtitleEditor",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SubtitleCore", targets: ["SubtitleCore"]),
        .executable(name: "SubtitleEditor", targets: ["SubtitleEditor"]),
    ],
    targets: [
        .target(name: "SubtitleCore"),
        .executableTarget(name: "SubtitleEditor", dependencies: ["SubtitleCore"]),
        .testTarget(name: "SubtitleCoreTests", dependencies: ["SubtitleCore"]),
    ]
)
