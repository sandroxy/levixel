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
            checksum: "393dd3e3416f3160df9f34f2232870b18840a3514ed1591733131b656253eeca"
        )
    ]
)
