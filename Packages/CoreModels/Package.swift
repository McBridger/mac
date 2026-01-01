// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "CoreModels",
    platforms: [.macOS(.v13)],
    products: [
        .library(
            name: "CoreModels",
            targets: ["CoreModels"]
        ),
    ],
    dependencies: [
        .package(path: "../EncryptionService")
    ],
    targets: [
        .target(
            name: "CoreModels",
            dependencies: ["EncryptionService"]
        ),
        .testTarget(
            name: "CoreModelsTests",
            dependencies: ["CoreModels"]
        ),
    ]
)