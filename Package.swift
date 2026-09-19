// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacResourceMonitor",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MacResourceMonitor", targets: ["MacResourceMonitor"])
    ],
    targets: [
        .executableTarget(
            name: "MacResourceMonitor",
            path: "Sources/MacResourceMonitor"
        )
    ]
)
