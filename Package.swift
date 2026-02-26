// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "URLSafeClipboard",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "URLSafeClipboard", targets: ["URLSafeClipboard"])
    ],
    targets: [
        .executableTarget(
            name: "URLSafeClipboard",
            path: "Sources/URLSafeClipboard"
        )
    ]
)
