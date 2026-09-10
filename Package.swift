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
            url: "https://github.com/sandroxy/levixel/releases/download/1.4.0/levixel-1.4.0.xcframework.zip",
            checksum: "e28c19a276bc9e712171780d869ff5bf6b6a33d3737a7e9c5a5309861562daef"
        )
    ]
)
