// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MediaDownloader",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DownloaderCore", targets: ["DownloaderCore"]),
        .library(name: "DownloaderPresentation", targets: ["DownloaderPresentation"]),
        .executable(name: "MediaDownloader", targets: ["MediaDownloaderApp"]),
        .executable(name: "ProcessFixture", targets: ["ProcessFixture"])
    ],
    targets: [
        .target(name: "ProcessSupervision"),
        .target(name: "DownloaderCore", dependencies: ["ProcessSupervision"]),
        .target(name: "ProcessFixtureSupport"),
        .executableTarget(name: "ProcessFixture", dependencies: ["ProcessFixtureSupport", "DownloaderCore"]),
        .target(name: "DownloaderPresentation", dependencies: ["DownloaderCore"]),
        .executableTarget(name: "MediaDownloaderApp", dependencies: ["DownloaderPresentation"]),
        .testTarget(name: "DownloaderPresentationTests", dependencies: ["DownloaderPresentation"]),
        .testTarget(name: "DownloaderCoreTests", dependencies: ["DownloaderCore", "ProcessFixtureSupport"],
                    resources: [.copy("Fixtures")])
    ],
    swiftLanguageModes: [.v6]
)
