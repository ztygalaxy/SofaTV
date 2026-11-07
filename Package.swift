// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "SofaTV",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SofaTV", targets: ["SofaTV"]),
        .executable(name: "SofaTVUpdater", targets: ["SofaTVUpdater"])
    ],
    targets: [
        .target(name: "UpdateSupport"),
        .executableTarget(name: "SofaTV", dependencies: ["UpdateSupport"]),
        .executableTarget(name: "SofaTVUpdater", dependencies: ["UpdateSupport"]),
        .testTarget(name: "OnlineChannelTests", dependencies: ["SofaTV"], path: "tests/OnlineChannels")
    ]
)
