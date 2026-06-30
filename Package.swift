// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SpeechAccuracyKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "SpeechAccuracyKit", targets: ["SpeechAccuracyKit"]),
        .executable(name: "fixture-gen", targets: ["fixture-gen"])
    ],
    targets: [
        .target(
            name: "SpeechAccuracyKit",
            dependencies: []
        ),
        .executableTarget(
            name: "fixture-gen",
            dependencies: ["SpeechAccuracyKit"]
        ),
        .testTarget(
            name: "SpeechAccuracyKitTests",
            dependencies: ["SpeechAccuracyKit"],
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
)
