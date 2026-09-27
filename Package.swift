// swift-tools-version:5.9
// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

import PackageDescription

let package = Package(
    name: "MenuCrane",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MenuCrane", targets: ["MenuCrane"]),
        .library(name: "MenuCraneCore", targets: ["MenuCraneCore"]),
    ],
    dependencies: [
        .package(path: "../StatusItemKit"),
        .package(path: "../HotkeyKit"),
    ],
    targets: [
        .target(name: "MenuCraneCore", dependencies: [.product(name: "HotkeyKit", package: "HotkeyKit")]),
        .executableTarget(
            name: "MenuCrane",
            dependencies: [
                "MenuCraneCore",
                .product(name: "StatusItemKit", package: "StatusItemKit"),
                .product(name: "HotkeyKit", package: "HotkeyKit"),
            ]
        ),
        .testTarget(name: "MenuCraneCoreTests", dependencies: ["MenuCraneCore"]),
    ]
)
