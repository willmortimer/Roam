// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "RoamSSH",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "RoamSSH", targets: ["RoamSSH"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Lakr233/libssh2-spm.git", from: "1.11.1"),
    ],
    targets: [
        .target(
            name: "RoamSSH",
            dependencies: [
                .product(name: "CSSH2", package: "libssh2-spm"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
