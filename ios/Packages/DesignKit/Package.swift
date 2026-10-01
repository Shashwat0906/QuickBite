// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DesignKit",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "DesignKit", targets: ["DesignKit"]),
    ],
    targets: [
        .target(name: "DesignKit"),
        .testTarget(name: "DesignKitTests", dependencies: ["DesignKit"]),
    ]
)
