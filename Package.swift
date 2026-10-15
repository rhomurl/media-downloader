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
        .target(name: "ProcessSupervision"),
        .target(name: "DownloaderCore", dependencies: ["ProcessSupervision"]),
        .target(name: "ProcessFixtureSupport"),
        .executableTarget(name: "ProcessFixture", dependencies: ["ProcessFixtureSupport", "DownloaderCore"]),
        .executableTarget(name: "MediaDownloaderApp", dependencies: ["DownloaderCore"]),
        .testTarget(name: "DownloaderCoreTests", dependencies: ["DownloaderCore", "ProcessFixtureSupport"],
                    resources: [.copy("Fixtures")])
    ],
    swiftLanguageModes: [.v6]
)
