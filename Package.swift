// swift-tools-version:6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// Conditional targets based on platform
#if os(Linux)
let runtimeProducts: [Product] = [
    .library(name: "EndpointsGeneratorConfig", targets: ["EndpointsGeneratorConfig"]),
    .library(
        name: "Endpoints",
        targets: ["Endpoints"]),
]

let runtimeTargets: [Target] = [
    .target(
        name: "Endpoints",
        dependencies: []),
    .testTarget(
        name: "EndpointsTests",
        dependencies: ["Endpoints"]),
]
#else
let runtimeProducts: [Product] = [
    .library(name: "EndpointsGeneratorConfig", targets: ["EndpointsGeneratorConfig"]),
    .library(
        name: "Endpoints",
        targets: ["Endpoints"]),
    .library(
        name: "EndpointsMocking",
        targets: ["EndpointsMocking"]),
]

let runtimeTargets: [Target] = [
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

let generatorTrait = "OpenAPIGenerator"
let generatorTargets: [Target] = [
    .target(name: "EndpointsGeneratorConfig", dependencies: []),
    .testTarget(name: "EndpointsGeneratorConfigTests", dependencies: ["EndpointsGeneratorConfig"]),
    .target(name: "EndpointsGeneratorCore", dependencies: [
        "EndpointsGeneratorConfig",
        .product(name: "OpenAPIKit", package: "OpenAPIKit", condition: .when(traits: [generatorTrait])),
        .product(name: "OpenAPIKit30", package: "OpenAPIKit", condition: .when(traits: [generatorTrait])),
        .product(name: "OpenAPIKitCompat", package: "OpenAPIKit", condition: .when(traits: [generatorTrait])),
        .product(name: "Yams", package: "Yams", condition: .when(traits: [generatorTrait])),
    ], exclude: ["Lowering/ORDERING.md"]),
    .executableTarget(name: "endpoints-generate", dependencies: ["EndpointsGeneratorCore"]),
    .plugin(name: "EndpointsGeneratorPlugin", capability: .buildTool(), dependencies: ["endpoints-generate"]),
    .testTarget(name: "EndpointsGeneratorCoreTests", dependencies: ["EndpointsGeneratorCore", "endpoints-generate"], resources: [.copy("Fixtures")]),
    .testTarget(name: "EndpointsGeneratedGoldenTests", dependencies: ["Endpoints"]),
]

let package = Package(
    name: "Endpoints",
    platforms: [
        .iOS(.v13),
        .tvOS(.v13),
        .macOS(.v10_15),
        .watchOS(.v6)
    ],
    products: runtimeProducts + [.plugin(name: "EndpointsGeneratorPlugin", targets: ["EndpointsGeneratorPlugin"])],
    traits: [
        .trait(name: generatorTrait, description: "Builds the OpenAPI generator and fetches OpenAPIKit and Yams."),
        .default(enabledTraits: [generatorTrait]),
    ],
    dependencies: [
        .package(url: "https://github.com/mattpolzin/OpenAPIKit.git", exact: "6.4.0", traits: []),
        .package(url: "https://github.com/jpsim/Yams.git", exact: "6.2.2"),
    ],
    targets: runtimeTargets + generatorTargets
)
