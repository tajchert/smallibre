// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Smallibre",
    platforms: [.macOS(.v14)],
    products: [.library(name: "SmallibreCore", targets: ["SmallibreCore"]), .executable(name: "Smallibre", targets: ["SmallibreApp"]), .executable(name: "SmallibreReaderHelper", targets: ["SmallibreReaderHelper"])],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .systemLibrary(name: "CZlib"),
        .target(name: "SmallibreCore", dependencies: ["CSQLite", "CZlib"]),
        .executableTarget(name: "SmallibreApp", dependencies: ["SmallibreCore"]),
        .executableTarget(name: "SmallibreReaderHelper", dependencies: ["SmallibreCore"]),
        .testTarget(name: "SmallibreAppTests", dependencies: ["SmallibreApp", "SmallibreCore"]),
        .testTarget(name: "SmallibreCoreTests", dependencies: ["SmallibreCore"], resources: [.copy("Fixtures")])
    ]
)
