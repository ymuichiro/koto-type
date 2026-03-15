// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "KotoType",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "KotoType",
            targets: ["KotoType"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.9.0")
    ],
    targets: [
        .executableTarget(
            name: "KotoType",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources",
            resources: [
                .process("KotoType/Resources")
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks"
                ], .when(platforms: [.macOS]))
            ]
        ),
        .testTarget(
            name: "KotoTypeTests",
            dependencies: ["KotoType"],
            path: "Tests"
        )
    ]
)
