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
            url: "https://github.com/sandroxy/levixel/releases/download/1.1.0/levixel-1.1.0.xcframework.zip",
            checksum: "b6cdbbb105765afec1aac0580a666e72da466dacc38211c22cded26238b278a9"
        )
    ]
)
