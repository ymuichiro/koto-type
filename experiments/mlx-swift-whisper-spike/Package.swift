// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "MLXSwiftWhisperSpike",
    platforms: [.macOS(.v14)],
    products: [
        .executable(
            name: "mlx-swift-whisper-spike",
            targets: ["MLXSwiftWhisperSpike"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift.git", from: "0.31.3")
    ],
    targets: [
        .target(
            name: "MLXSwiftWhisperSpikeCore",
            path: "Sources/MLXSwiftWhisperSpikeCore"
        ),
        .executableTarget(
            name: "MLXSwiftWhisperSpike",
            dependencies: [
                "MLXSwiftWhisperSpikeCore",
                .product(name: "MLX", package: "mlx-swift")
            ],
            path: "Sources/MLXSwiftWhisperSpike"
        ),
        .testTarget(
            name: "MLXSwiftWhisperSpikeTests",
            dependencies: ["MLXSwiftWhisperSpikeCore"],
            path: "Tests/MLXSwiftWhisperSpikeTests"
        )
    ]
)
