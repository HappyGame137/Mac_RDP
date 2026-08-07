// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MacRDPLowLatency",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MacRDPLowLatency", targets: ["MacRDPLowLatency"])
    ],
    targets: [
        .executableTarget(
            name: "MacRDPLowLatency",
            path: "Sources/MacRDPLowLatency"
        ),
        .testTarget(
            name: "MacRDPLowLatencyTests",
            dependencies: ["MacRDPLowLatency"],
            path: "Tests/MacRDPLowLatencyTests"
        )
    ]
)
