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
            url: "https://github.com/sandroxy/levixel/releases/download/1.2.0/levixel-1.2.0.xcframework.zip",
            checksum: "8fdc9cf2185b26e46889addaa9a46962dbfddb73276fe5056b06132187678e66"
        )
    ]
)
