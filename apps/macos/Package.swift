// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Recny",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "RecnyCore", targets: ["RecnyCore"]),
        .executable(name: "Recny", targets: ["Recny"])
    ],
    targets: [
        .target(
            name: "RecnyCore",
            path: "Sources/RecnyCore",
            resources: [.copy("Resources/recny_local_notes.py")],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "Recny",
            dependencies: ["RecnyCore"],
            path: "Sources/Recny",
            exclude: ["Resources/Info.plist"]
        ),
        .executableTarget(
            name: "RecnyMicSmokeTest",
            dependencies: ["RecnyCore"],
            path: "Sources/RecnyMicSmokeTest",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("ScreenCaptureKit")
            ]
        ),
        .executableTarget(
            name: "RecnySystemAudioSmokeTest",
            dependencies: ["RecnyCore"],
            path: "Sources/RecnySystemAudioSmokeTest",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("ScreenCaptureKit")
            ]
        ),
        .testTarget(
            name: "RecnyCoreTests",
            dependencies: ["RecnyCore"],
            path: "Tests/RecnyCoreTests"
        )
    ]
)
