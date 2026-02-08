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
    dependencies: [],
    targets: [
        .executableTarget(
            name: "KotoType",
            dependencies: [],
            path: "Sources",
            resources: [
                .process("KotoType/Resources")
            ]
        ),
        .testTarget(
            name: "KotoTypeTests",
            dependencies: ["KotoType"],
            path: "Tests"
        )
    ]
)
