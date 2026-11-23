// swift-tools-version: 6.0
import PackageDescription

// The `hush` command-line tool. The generator itself is the HushCore package in Core/.
let package = Package(
    name: "hush",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "hush", targets: ["hush"]),
    ],
    dependencies: [
        .package(path: "Core"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "hush",
            dependencies: [
                .product(name: "HushCore", package: "Core"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
    ]
)
