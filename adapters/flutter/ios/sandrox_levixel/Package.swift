// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "sandrox_levixel",
    platforms: [.iOS("15.0")],
    products: [.library(name: "sandrox-levixel", targets: ["sandrox_levixel"])],
    dependencies: [.package(name: "FlutterFramework", path: "../FlutterFramework")],
    targets: [
        .target(name: "sandrox_levixel", dependencies: [
            .product(name: "FlutterFramework", package: "FlutterFramework"), "Levixel"
        ]),
        .binaryTarget(name: "Levixel", path: "Frameworks/Levixel.xcframework")
    ]
)
