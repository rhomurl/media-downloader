// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MediaDownloader",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DownloaderCore", targets: ["DownloaderCore"]),
        .executable(name: "MediaDownloader", targets: ["MediaDownloaderApp"])
    ],
    targets: [
        .target(name: "DownloaderCore"),
        .executableTarget(name: "MediaDownloaderApp", dependencies: ["DownloaderCore"]),
        .testTarget(name: "DownloaderCoreTests", dependencies: ["DownloaderCore"])
    ],
    swiftLanguageModes: [.v6]
)
