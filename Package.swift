// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SwiftDL",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SwiftDL", targets: ["SwiftDL"])
    ],
    targets: [
        .executableTarget(
            name: "SwiftDL",
            path: "Sources/SwiftDL",
            exclude: ["Resources/Info.plist"],
            resources: [
                .process("Resources/AppIcon.icns")
            ]
        )
    ]
)
