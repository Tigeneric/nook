// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Nook",
    // English is the base language: an untranslated system language falls back to it.
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "NookCore", targets: ["NookCore"]),
        .library(name: "NookSheet", targets: ["NookSheet"]),
        .executable(name: "Nook", targets: ["Nook"]),
    ],
    targets: [
        // Model, request parsing, finding free windows, cell addressing. No I/O.
        .target(
            name: "NookCore",
            path: "Sources/NookCore"
        ),

        // Loading the sheet’s CSV export and parsing the space tabs.
        .target(
            name: "NookSheet",
            dependencies: ["NookCore"],
            path: "Sources/NookSheet"
        ),

        // The overlay: NSPanel, the global hot key, the menu bar item.
        .executableTarget(
            name: "Nook",
            dependencies: ["NookCore", "NookSheet"],
            path: "Sources/Nook",
            exclude: ["Info.plist"],
            resources: [.process("Resources")]
        ),

        .testTarget(
            name: "NookCoreTests",
            dependencies: ["NookCore"],
            path: "Tests/NookCoreTests"
        ),
        .testTarget(
            name: "NookSheetTests",
            dependencies: ["NookSheet", "NookCore"],
            path: "Tests/NookSheetTests"
        ),
        .testTarget(
            name: "NookTests",
            dependencies: ["Nook", "NookCore", "NookSheet"],
            path: "Tests/NookTests"
        ),
    ]
)
