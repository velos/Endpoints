// swift-tools-version:5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Endpoints",
    platforms: [
        .iOS(.v13),
        .tvOS(.v13),
        .macOS(.v10_15),
        .watchOS(.v6)
    ],
    products: [
        .library(
            name: "Endpoints",
            targets: ["Endpoints"]),
        .executable(name: "generate-endpoints", targets: ["generate-endpoints"]),
        .plugin(
            name: "GenerateEndpoints",
            targets: ["GenerateEndpoints"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.1.4"),
        .package(url: "https://github.com/yonaskolb/SwagGen", from: "4.7.0"),
    ],
    targets: [
        .target(
            name: "Endpoints",
            dependencies: []),
        .plugin(
            name: "GenerateEndpoints",
            capability: .buildTool(),
            dependencies: ["generate-endpoints"]),
        .executableTarget(
            name: "generate-endpoints",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "SwagGenKit", package: "SwagGen"),
            ]),
        .testTarget(
            name: "EndpointsTests",
            dependencies: ["Endpoints"]),
    ]
)
