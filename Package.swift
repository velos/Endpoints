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
        .executable(name: "generate-endpoints", targets: ["generate-endpoints"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.1"),
        .package(url: "https://github.com/mattpolzin/OpenAPIKit", from: "2.5.1"),
        .package(url: "https://github.com/jpsim/Yams", from: "5.0.0"),
        .package(url: "https://github.com/apple/swift-syntax.git", from: "509.0.2"),
    ],
    targets: [
        .target(
            name: "Endpoints",
            dependencies: []),
        .testTarget(
            name: "EndpointsTests",
            dependencies: ["Endpoints"]),
        .executableTarget(
            name: "generate-endpoints",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "OpenAPIKit", package: "OpenAPIKit"),
                .product(name: "Yams", package: "Yams"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                "Endpoints"
            ],
            path: "Sources/GenerateEndpoints"),
    ]
)
