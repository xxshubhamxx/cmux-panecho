// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OwlRenderFixture",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "OwlLayerHostVerifier",
            targets: ["OwlLayerHostVerifier"]
        ),
        .executable(
            name: "OwlLayerHostSelfTest",
            targets: ["OwlLayerHostSelfTest"]
        )
    ],
    targets: [
        .executableTarget(
            name: "OwlLayerHostVerifier",
            path: "Sources/OwlLayerHostVerifier"
        ),
        .executableTarget(
            name: "OwlLayerHostSelfTest",
            path: "Sources/OwlLayerHostSelfTest"
        )
    ]
)
