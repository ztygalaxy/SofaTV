// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "SofaTV", platforms: [.macOS(.v14)], products: [.executable(name: "SofaTV", targets: ["SofaTV"])], targets: [.executableTarget(name: "SofaTV", resources: [.process("Resources")])])
