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
            url: "https://gitee.com/sandrox/levixel/releases/download/1.0.0/levixel-1.0.0.xcframework.zip",
            checksum: "8807c7cb09df1a35d7bb6cff07fa990c2e313912ec44f650b0f509014379d2c7"
        )
    ]
)
