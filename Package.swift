// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Universo",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(name: "Universo", path: "Sources/Universo")
    ],
    swiftLanguageModes: [.v5]
)
