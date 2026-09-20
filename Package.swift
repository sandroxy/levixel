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
            checksum: "d60899928fc4af1a5bac8dcac18258a6eff55d4bd34e42acd8db65c19decad96"
        )
    ]
)
