// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PixfunNative",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Pixfun", targets: ["Pixfun"])],
    targets: [
        .executableTarget(name: "Pixfun", path: "Sources/Pixfun")
    ]
)
