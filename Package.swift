// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Nitpick",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "Nitpick", targets: ["Nitpick"]),
    ],
    targets: [
        .target(
            name: "Nitpick",
            resources: [.process("PrivacyInfo.xcprivacy")]
        ),
        .testTarget(
            name: "NitpickTests",
            dependencies: ["Nitpick"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
