// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ast-grep-mcp-swift",
    products: [
        .library(
            name: "ast-grep-mcp-swift",
            targets: ["ast-grep-mcp-swift"]
        ),
    ],
    targets: [
        .target(
            name: "ast-grep-mcp-swift"
        ),
        .testTarget(
            name: "ast-grep-mcp-swiftTests",
            dependencies: ["ast-grep-mcp-swift"]
        ),
    ]
)
