// swift-tools-version:6.1
import PackageDescription
let package = Package(
    name: "RuntimeOnlyClient",
    platforms: [.macOS(.v10_15), .iOS(.v13)],
    dependencies: [.package(name: "Endpoints", path: "../..", traits: [])],
    targets: [
        .target(name: "RuntimeOnlyClient", dependencies: [.product(name: "Endpoints", package: "Endpoints")]),
        .testTarget(name: "RuntimeOnlyClientTests", dependencies: ["RuntimeOnlyClient"]),
    ]
)
