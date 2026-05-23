// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TOrbitRecorder",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "TOrbitRecorderCore", targets: ["TOrbitRecorderCore"]),
        .executable(name: "TOrbitRecorder", targets: ["TOrbitRecorder"])
    ],
    targets: [
        .target(
            name: "TOrbitRecorderCore",
            path: "Sources/TOrbitRecorderCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "TOrbitRecorder",
            dependencies: ["TOrbitRecorderCore"],
            path: "Sources/TOrbitRecorder",
            exclude: ["Resources/Info.plist"]
        ),
        .testTarget(
            name: "TOrbitRecorderCoreTests",
            dependencies: ["TOrbitRecorderCore"],
            path: "Tests/TOrbitRecorderCoreTests"
        )
    ]
)
