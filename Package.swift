// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TypingStats",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "TypingStats", targets: ["TypingStats"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.29.0"),
        .package(url: "https://github.com/swiftlang/swift-testing.git", from: "0.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "TypingStats",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/TypingStats"
        ),
        .testTarget(
            name: "TypingStatsTests",
            dependencies: [
                "TypingStats",
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "Tests/TypingStatsTests"
        ),
    ]
)
