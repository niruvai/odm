// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ODM",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ODM",
            path: "Sources/ODM"
        )
    ]
)
