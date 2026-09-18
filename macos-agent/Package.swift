// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DeviceIQAgent",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "DeviceIQAgent",
            path: "Sources/DeviceIQAgent"
        )
    ]
)
