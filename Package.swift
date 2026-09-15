// swift-tools-version:6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.
import PackageDescription

let package = Package(
    name: "AsyncNavigation",
    platforms: [
        .macOS(.v15), .iOS(.v18), .tvOS(.v18)
    ],
    products: [
        .library(
            name: "AsyncNavigation",
            targets: ["AsyncNavigation"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-async-algorithms.git", exact: "1.1.5")
    ],
    targets: [
        .target(
            name: "AsyncNavigation",
            dependencies: [.product(name: "AsyncAlgorithms", package: "swift-async-algorithms")],
            swiftSettings: [
//                .unsafeFlags([
//                    "-Xfrontend",
//                    "-warn-long-function-bodies=100",
//                    "-Xfrontend",
//                    "-warn-long-expression-type-checking=100"
//                ])
            ]
        ),
        .testTarget(
            name: "AsyncNavigationTests",
            dependencies: ["AsyncNavigation"]
        )
    ],
    swiftLanguageModes: [.v5]
)
