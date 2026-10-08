// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Levixel",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "Levixel",
            targets: ["Levixel"]
        )
    ],
    targets: [
        .binaryTarget(
            name: "Levixel",
            url: "https://github.com/sandroxy/levixel/releases/download/1.5.0/levixel-1.5.0.xcframework.zip",
            checksum: "afde6311cd1cc08e6e30158ea8bda22cec5ddec5a62630dc8fb5bef8ef4b7810"
        )
    ]
)
