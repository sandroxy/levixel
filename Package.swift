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
            url: "https://github.com/sandroxy/levixel/releases/download/1.1.1/levixel-1.1.1.xcframework.zip",
            checksum: "def7afdfe1cc6c67e243f6bf1806c452b07949c7d45bd974bb1e413651defdae"
        )
    ]
)
