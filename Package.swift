// swift-tools-version:6.0
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
        .library(
            name: "EndpointsMocking",
            targets: ["EndpointsMocking"]),
    ],
    targets: [
        .target(
            name: "Endpoints",
            dependencies: []),
        .target(
            name: "EndpointsMocking",
            dependencies: ["Endpoints"]),
        .testTarget(
            name: "EndpointsTests",
            dependencies: ["Endpoints"]),
        .testTarget(
            name: "EndpointsMockingTests",
            dependencies: ["EndpointsMocking"]),
    ]
)
