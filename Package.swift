// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacResourceMonitor",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MacResourceMonitor", targets: ["MacResourceMonitor"]),
        .executable(name: "MacResourceMonitorMCP", targets: ["MacResourceMonitorMCP"])
    ],
    targets: [
        .target(
            name: "MacResourceMonitorCore",
            path: "Sources/MacResourceMonitorCore"
        ),
        .executableTarget(
            name: "MacResourceMonitor",
            dependencies: ["MacResourceMonitorCore"],
            path: "Sources/MacResourceMonitor"
        ),
        .executableTarget(
            name: "MacResourceMonitorMCP",
            dependencies: ["MacResourceMonitorCore"],
            path: "Sources/MacResourceMonitorMCP"
        )
    ]
)
