// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacResourceMonitor",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MacResourceMonitor", targets: ["MacResourceMonitor"]),
        .executable(name: "MacResourceMonitorMCP", targets: ["MacResourceMonitorMCP"]),
        .executable(name: "MacResourceMonitorTestRunner", targets: ["MacResourceMonitorTestRunner"])
    ],
    targets: [
        .target(
            name: "MacResourceMonitorCore",
            path: "Sources/MacResourceMonitorCore"
        ),
        .target(
            name: "MacResourceMonitorMCPCore",
            dependencies: ["MacResourceMonitorCore"],
            path: "Sources/MacResourceMonitorMCPCore"
        ),
        .executableTarget(
            name: "MacResourceMonitor",
            dependencies: ["MacResourceMonitorCore"],
            path: "Sources/MacResourceMonitor"
        ),
        .executableTarget(
            name: "MacResourceMonitorMCP",
            dependencies: ["MacResourceMonitorCore", "MacResourceMonitorMCPCore"],
            path: "Sources/MacResourceMonitorMCP"
        ),
        .executableTarget(
            name: "MacResourceMonitorTestRunner",
            dependencies: ["MacResourceMonitorCore", "MacResourceMonitorMCPCore"],
            path: "Sources/MacResourceMonitorTestRunner"
        )
    ]
)
