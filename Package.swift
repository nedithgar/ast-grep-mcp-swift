// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ast-grep-mcp-swift",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(
            name: "ast-grep-mcp-swift",
            targets: ["ast-grep-mcp-swift"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.10.2"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.6.2")
    ],
    targets: [
        .executableTarget(
            name: "ast-grep-mcp-swift",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "Yams", package: "Yams"),
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .testTarget(
            name: "ast-grep-mcp-swiftTests",
            dependencies: ["ast-grep-mcp-swift"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
