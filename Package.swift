// swift-tools-version:5.9
// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

import PackageDescription

let package = Package(
    name: "MenuCrane",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MenuCraneCore", targets: ["MenuCraneCore"]),
    ],
    dependencies: [
        .package(path: "../HotkeyKit"),
    ],
    targets: [
        .target(name: "MenuCraneCore", dependencies: [.product(name: "HotkeyKit", package: "HotkeyKit")]),
        .testTarget(name: "MenuCraneCoreTests", dependencies: ["MenuCraneCore"]),
    ]
)
