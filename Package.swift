// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "RealityKitFormats",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "RealityKitFormats",
            targets: ["RealityKitFormats"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/radcli14/ModelIO-to-RealityKit", from: "0.4.1"),
        .package(url: "https://github.com/radcli14/DAE-to-RealityKit", from: "0.4.1"),
        .package(url: "https://github.com/radcli14/GLTFKit2", branch: "realitykit-export"),
    ],
    targets: [
        .target(
            name: "RealityKitFormats",
            dependencies: [
                .product(name: "ModelIO-to-RealityKit", package: "ModelIO-to-RealityKit"),
                .product(name: "DAE-to-RealityKit", package: "DAE-to-RealityKit"),
                .product(name: "GLTFKit2", package: "GLTFKit2"),
            ]
        ),
        .testTarget(
            name: "RealityKitFormatsTests",
            dependencies: ["RealityKitFormats"]
        ),
    ]
)
