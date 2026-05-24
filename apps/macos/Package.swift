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
                .linkedFramework("AVFoundation"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "TOrbitRecorder",
            dependencies: ["TOrbitRecorderCore"],
            path: "Sources/TOrbitRecorder",
            exclude: ["Resources/Info.plist"]
        ),
        .executableTarget(
            name: "TOrbitRecorderMicSmokeTest",
            dependencies: ["TOrbitRecorderCore"],
            path: "Sources/TOrbitRecorderMicSmokeTest",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("ScreenCaptureKit")
            ]
        ),
        .executableTarget(
            name: "TOrbitRecorderSystemAudioSmokeTest",
            dependencies: ["TOrbitRecorderCore"],
            path: "Sources/TOrbitRecorderSystemAudioSmokeTest",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("ScreenCaptureKit")
            ]
        ),
        .testTarget(
            name: "TOrbitRecorderCoreTests",
            dependencies: ["TOrbitRecorderCore"],
            path: "Tests/TOrbitRecorderCoreTests"
        )
    ]
)
