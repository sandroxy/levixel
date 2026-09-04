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
            checksum: "489a4b3dfa1a417bbab859d6e252e0e1baba81b1becbe8453f5aeaf9f68cdb10"
        )
    ]
)
