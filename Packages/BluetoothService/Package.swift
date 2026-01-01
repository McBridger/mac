// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "BluetoothService",
    platforms: [.macOS(.v13)],
    products: [
        .library(
            name: "BluetoothService",
            targets: ["BluetoothService"]
        ),
    ],
    dependencies: [
        .package(path: "../CoreModels"),
        .package(path: "../EncryptionService")
    ],
    targets: [
        .target(
            name: "BluetoothService",
            dependencies: ["CoreModels", "EncryptionService"]
        ),
        .testTarget(
            name: "BluetoothServiceTests",
            dependencies: ["BluetoothService"]
        ),
    ]
)