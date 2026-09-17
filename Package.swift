// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ImageInspector",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ImageInspector",
            path: "Sources/ImageInspector"
        )
    ]
)
