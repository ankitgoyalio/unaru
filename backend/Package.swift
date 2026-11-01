// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "Backend",
    platforms: [
        .macOS(.v15),
    ],
    dependencies: [
        .package(path: "../packages/Shared"),
        .package(url: "https://github.com/ankitgoyalio/swiftkiteconnect.git", exact: "0.1.0"),
        // 💧 A server-side Swift web framework.
        .package(url: "https://github.com/vapor/vapor.git", from: "4.121.4"),
        // 🔵 Non-blocking, event-driven networking for Swift. Used for custom executors
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.101.0"),
    ],
    targets: [
        .executableTarget(
            name: "Backend",
            dependencies: [
                .product(name: "Shared", package: "Shared"),
                .product(name: "KiteConnect", package: "swiftkiteconnect"),
                .product(name: "Vapor", package: "vapor"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
            ],
            swiftSettings: swiftSettings,
        ),
        .testTarget(
            name: "BackendTests",
            dependencies: [
                .target(name: "Backend"),
                .product(name: "KiteConnect", package: "swiftkiteconnect"),
                .product(name: "VaporTesting", package: "vapor"),
            ],
            swiftSettings: swiftSettings,
        ),
    ],
)

var swiftSettings: [SwiftSetting] {
    [
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("MemberImportVisibility"),
        .enableUpcomingFeature("InferIsolatedConformances"),
        .enableUpcomingFeature("ImmutableWeakCaptures"),
    ]
}
