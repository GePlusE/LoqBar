// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "LoqBar",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "LoqBar",
            targets: ["LoqBar"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "LoqBar",
            path: "Sources"
        ),
        .testTarget(
            name: "LoqBarTests",
            dependencies: ["LoqBar"],
            path: "Tests/LoqBarTests"
        ),
    ]
)
