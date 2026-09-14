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
            url: "https://github.com/sandroxy/levixel/releases/download/1.4.1/levixel-1.4.1.xcframework.zip",
            checksum: "8e21564c0f958a9b68bfeeda0e592467742e28e504f1554d815374649a73292b"
        )
    ]
)
