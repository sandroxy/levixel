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
            checksum: "6efb0d57d710a566ceb4ecb1d0ced0ba9e9111bc9a1536f64a571a3f7f3cb9e9"
        )
    ]
)
