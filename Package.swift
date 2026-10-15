// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MediaDownloader",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DownloaderCore", targets: ["DownloaderCore"]),
        .executable(name: "MediaDownloader", targets: ["MediaDownloaderApp"]),
        .executable(name: "ProcessFixture", targets: ["ProcessFixture"])
    ],
    targets: [
        .target(name: "DownloaderCore"),
        .target(name: "ProcessFixtureSupport"),
        .executableTarget(name: "ProcessFixture", dependencies: ["ProcessFixtureSupport", "DownloaderCore"]),
        .executableTarget(name: "MediaDownloaderApp", dependencies: ["DownloaderCore"]),
        .testTarget(name: "DownloaderCoreTests", dependencies: ["DownloaderCore"])
    ],
    swiftLanguageModes: [.v6]
)
