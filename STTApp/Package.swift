// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "STTApp",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "STTApp",
            targets: ["STTApp"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "STTApp",
            dependencies: [],
            path: "Sources"
        ),
        .testTarget(
            name: "STTAppTests",
            dependencies: ["STTApp"],
            path: "Tests"
        )
    ]
)
