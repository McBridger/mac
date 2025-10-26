// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ClipboardService",
    platforms: [.macOS(.v13)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "ClipboardService",
            targets: ["ClipboardService"]
        ),
    ],
    dependencies: [
        .package(path: "../CoreModels")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "ClipboardService",
            dependencies: ["CoreModels"]
        ),
        .testTarget(
            name: "ClipboardServiceTests",
            dependencies: ["ClipboardService"]
        ),
    ]
)
