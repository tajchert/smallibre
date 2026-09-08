// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CalibreNova",
    platforms: [.macOS(.v14)],
    products: [.library(name: "NovaCore", targets: ["NovaCore"]), .executable(name: "CalibreNova", targets: ["NovaApp"]), .executable(name: "NovaReaderHelper", targets: ["NovaReaderHelper"])],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .systemLibrary(name: "CZlib"),
        .target(name: "NovaCore", dependencies: ["CSQLite", "CZlib"]),
        .executableTarget(name: "NovaApp", dependencies: ["NovaCore"]),
        .executableTarget(name: "NovaReaderHelper", dependencies: ["NovaCore"]),
        .testTarget(name: "NovaCoreTests", dependencies: ["NovaCore"], resources: [.copy("Fixtures")])
    ]
)
