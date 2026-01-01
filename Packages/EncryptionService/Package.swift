// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EncryptionService",
    platforms: [.macOS(.v13)],
    products: [
        .library(
            name: "EncryptionService",
            targets: ["EncryptionService"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "EncryptionService",
            dependencies: []
        ),
    ]
)