// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Snowdrift",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Snowdrift",
            path: "Sources/Snowdrift",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("AVFoundation"),
            ]
        )
    ]
)
