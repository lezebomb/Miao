// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MiaomiaoMac",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "Miaomiao", targets: ["Miaomiao"])
    ],
    targets: [
        .target(name: "MiaomiaoCore"),
        .executableTarget(
            name: "Miaomiao",
            dependencies: ["MiaomiaoCore"]
        ),
        .testTarget(
            name: "MiaomiaoCoreTests",
            dependencies: ["MiaomiaoCore"]
        )
    ]
)
