// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "overwatchr",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "OverwatchrCore", targets: ["OverwatchrCore"]),
        .executable(name: "overwatchr", targets: ["overwatchr"]),
        .executable(name: "overwatchr-app", targets: ["OverwatchrApp"])
    ],
    targets: [
        .target(
            name: "OverwatchrCore",
            path: "Core"
        ),
        .executableTarget(
            name: "overwatchr",
            dependencies: ["OverwatchrCore"],
            path: "CLI"
        ),
        .executableTarget(
            name: "OverwatchrApp",
            dependencies: ["OverwatchrCore"],
            path: "App",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "OverwatchrCoreTests",
            dependencies: ["OverwatchrCore"],
            path: "Tests/OverwatchrCoreTests"
        )
    ]
)
