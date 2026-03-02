// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PurePaste",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "PurePaste", targets: ["PurePaste"])
    ],
    targets: [
        .executableTarget(
            name: "PurePaste",
            path: "source"
        )
    ]
)
