// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WeatherIsland",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "WeatherIsland",
            targets: ["WeatherIsland"]
        )
    ],
    targets: [
        .executableTarget(
            name: "WeatherIsland"
        )
    ]
)
