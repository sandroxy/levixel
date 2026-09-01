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
            url: "https://github.com/sandroxy/levixel/releases/download/1.3.0/levixel-1.3.0.xcframework.zip",
            checksum: "f76428472d481f3b82857ca4d50513b6bc2a99b8730a0f70f4f4f732c74f5d44"
        )
    ]
)
