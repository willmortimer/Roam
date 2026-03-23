// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "iDevSSH",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "iDevSSH", targets: ["iDevSSH"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Lakr233/libssh2-spm.git", from: "1.11.1"),
    ],
    targets: [
        .target(
            name: "iDevSSH",
            dependencies: [
                .product(name: "CSSH2", package: "libssh2-spm"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
