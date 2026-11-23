// swift-tools-version: 6.0
import PackageDescription

// The generator core, shared by the app (App/) and the CLI (root package).
// It lives in its own folder so the app project is not nested inside a package it depends on.
let package = Package(
    name: "HushCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HushCore", targets: ["HushCore"]),
    ],
    targets: [
        .target(name: "HushCore"),
        .testTarget(name: "HushCoreTests", dependencies: ["HushCore"]),
    ]
)
