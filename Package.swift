// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AppStoreManager",
    platforms: [.iOS(.v17), .macOS(.v11), .tvOS(.v14), .watchOS(.v7)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "AppStoreManager",
            targets: ["AppStoreManager"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(url: "https://github.com/Appracatappra/LogManager", .upToNextMajor(from: "1.0.1")),
        .package(url: "https://github.com/Appracatappra/SimpleSerializer", .upToNextMajor(from: "1.0.1")),
        .package(url: "https://github.com/Appracatappra/SwiftletUtilities", .upToNextMajor(from: "1.1.5")),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "AppStoreManager",
            dependencies: ["LogManager", "SimpleSerializer", "SwiftletUtilities"]
        ),
        .testTarget(
            name: "AppStoreManagerTests",
            dependencies: ["AppStoreManager"]),
    ]
)
