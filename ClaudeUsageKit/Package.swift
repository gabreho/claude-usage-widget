// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ClaudeUsageKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "ClaudeUsageKit",
            targets: ["ClaudeUsageKit"]
        )
    ],
    targets: [
        .target(
            name: "ClaudeUsageKit"
        )
    ]
)
