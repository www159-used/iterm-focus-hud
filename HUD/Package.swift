// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "FocusHUD",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "FocusHUD",
            path: "Sources/FocusHUD"
        )
    ]
)
