// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OpenDeskAdmin",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "OpenDeskCore", targets: ["OpenDeskCore"]),
        .executable(name: "opendesk", targets: ["OpenDeskCLI"]),
        .executable(name: "opendesk-gui", targets: ["OpenDeskGUI"]),
    ],
    targets: [
        .target(name: "OpenDeskCore", path: "Sources/OpenDeskCore"),
        .executableTarget(
            name: "OpenDeskCLI",
            dependencies: ["OpenDeskCore"],
            path: "Sources/OpenDeskCLI"
        ),
        .executableTarget(
            name: "OpenDeskGUI",
            dependencies: ["OpenDeskCore"],
            path: "Sources/OpenDeskGUI"
        ),
        .testTarget(
            name: "OpenDeskCoreTests",
            dependencies: ["OpenDeskCore"],
            path: "Tests/OpenDeskCoreTests"
        ),
    ]
)
