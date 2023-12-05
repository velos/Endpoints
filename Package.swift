// swift-tools-version:5.5
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
