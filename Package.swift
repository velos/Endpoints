// swift-tools-version:6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// Conditional targets based on platform
#if os(Linux)
let products: [Product] = [
    .library(
        name: "Endpoints",
        targets: ["Endpoints"]),
]

let targets: [Target] = [
    .target(
        name: "Endpoints",
        dependencies: []),
    .testTarget(
        name: "EndpointsTests",
        dependencies: ["Endpoints"]),
]
#else
let products: [Product] = [
    .library(
        name: "Endpoints",
        targets: ["Endpoints"]),
    .library(
        name: "EndpointsMocking",
        targets: ["EndpointsMocking"]),
]

let targets: [Target] = [
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
#endif

let package = Package(
    name: "Endpoints",
    platforms: [
        .iOS(.v13),
        .tvOS(.v13),
        .macOS(.v10_15),
        .watchOS(.v6)
    ],
    products: products,
    targets: targets
)
