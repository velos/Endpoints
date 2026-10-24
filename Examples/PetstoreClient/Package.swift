// swift-tools-version:6.1
import PackageDescription
let package = Package(
    name: "PetstoreClient",
    platforms: [.macOS(.v10_15), .iOS(.v13)],
    products: [.library(name: "PetstoreAPI", targets: ["PetstoreAPI"])],
    dependencies: [.package(name: "Endpoints", path: "../..")],
    targets: [
        .target(name: "PetstoreAPI", dependencies: [.product(name: "Endpoints", package: "Endpoints")], plugins: [.plugin(name: "EndpointsGeneratorPlugin", package: "Endpoints")]),
        .testTarget(name: "PetstoreClientTests", dependencies: ["PetstoreAPI", .product(name: "Endpoints", package: "Endpoints")]),
    ]
)
