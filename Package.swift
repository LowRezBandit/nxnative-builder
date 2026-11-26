// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NXNativeBuilder",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "NXNativeBuilder", targets: ["NXNativeBuilder"])
    ],
    targets: [
        .executableTarget(
            name: "NXNativeBuilder",
            path: "Sources",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "NXNativeBuilderTests",
            dependencies: ["NXNativeBuilder"],
            path: "Tests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
