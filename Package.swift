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
            checksum: "cc07fa6ac993becfa3a5873d5608812e36ded9457306a556f1b6dbc7170fa639"
        )
    ]
)
