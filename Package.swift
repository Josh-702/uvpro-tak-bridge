// swift-tools-version:5.9
// Copyright 2026 Josh Howard
// SPDX-License-Identifier: Apache-2.0

import PackageDescription

let package = Package(
    name: "UVBridgeCore",
    platforms: [
        .macOS(.v13),
        .iOS(.v17),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.12.0"),
    ],
    products: [
        .library(name: "UVBridgeCore", targets: ["UVBridgeCore"]),
    ],
    targets: [
        .target(
            name: "UVBridgeCore",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
            ]
        ),
        .testTarget(
            name: "UVBridgeCoreTests",
            dependencies: ["UVBridgeCore"]
        ),
    ]
)
