// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DNSLeakGuard",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "DNSLeakCore", targets: ["DNSLeakCore"]),
        .executable(name: "DNSLeakGuard", targets: ["DNSLeakGuardApp"])
    ],
    targets: [
        .target(
            name: "DNSLeakCore",
            path: "Sources/DNSLeakCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "DNSLeakGuardApp",
            dependencies: ["DNSLeakCore"],
            path: "Sources/DNSLeakGuardApp",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
