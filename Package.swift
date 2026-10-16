// swift-tools-version: 6.0
import PackageDescription

// Portable logic tests only. The iOS application is built using the Xcode project.
let package = Package(
    name: "RunTickLogic",
    products: [.library(name: "RunTick", targets: ["RunTick"])],
    targets: [
        .target(name: "RunTick", path: "RunTick/Core"),
        .testTarget(name: "RunTickTests", dependencies: ["RunTick"], path: "RunTickTests")
    ],
    swiftLanguageModes: [.v5]
)
