// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DesktopPet",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "DesktopPet",
            path: "Sources/DesktopPet"
        )
    ]
)
