// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Graphist",
    platforms: [
        .macOS(.v26) // macOS Tahoe and later
    ],
    products: [
        .executable(name: "Graphist", targets: ["Graphist"])
    ],
    targets: [
        .executableTarget(
            name: "Graphist",
            path: "Sources/Graphist",
            swiftSettings: [
                // The whole app (UI + rendering) runs on the main thread, driven by
                // MTKView's display link, so main-actor-by-default keeps Swift 6
                // concurrency checking simple.
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
            ]
        )
    ]
)
