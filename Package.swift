// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "opendesk-admin",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "OpenDeskCore", targets: ["OpenDeskCore"]),
        .executable(name: "opendesk", targets: ["OpenDeskCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "OpenDeskCore",
            path: "packages/core/Sources/OpenDeskCore",
            resources: [.copy("Resources/schema.sql")],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "OpenDeskCLI",
            dependencies: [
                "OpenDeskCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "apps/cli/Sources/OpenDeskCLI"
        ),
        .testTarget(
            name: "OpenDeskCoreTests",
            dependencies: ["OpenDeskCore"],
            path: "tests/OpenDeskCoreTests"
        ),
    ]
)
