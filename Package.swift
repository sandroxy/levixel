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
            checksum: "f8ea7479f16342dc2119038f9c4f4ff9c9c57888141efe6f47ba36aff8f703cc"
        )
    ]
)
