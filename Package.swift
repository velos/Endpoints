// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Endpoints",
    platforms: [
        .macOS(.v10_12),
        .iOS(.v10),
        .tvOS(.v9),
        .watchOS(.v3)
    ],
    products: [
        .library(
            name: "Endpoints",
            targets: ["Endpoints"]),
    ],
    targets: [
        .target(
            name: "Endpoints",
            dependencies: []),
        .testTarget(
            name: "EndpointsTests",
            dependencies: ["Endpoints"]),
    ]
)
