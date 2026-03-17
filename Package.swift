// swift-tools-version: 5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Kaset",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(
            name: "Kaset",
            targets: ["Kaset"]
        ),
        .executable(
            name: "api-explorer",
            targets: ["APIExplorer"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.8.1"),
    ],
    targets: [
        // Main app executable
        .executableTarget(
            name: "Kaset",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            resources: [
                .process("Resources"),
            ]
        ),
        // API Explorer CLI tool
        .executableTarget(
            name: "APIExplorer"
        ),
        // Unit tests
        .testTarget(
            name: "KasetTests",
            dependencies: ["Kaset"],
            resources: [
                .process("Fixtures"),
            ]
        ),
    ]
)
