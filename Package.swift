// swift-tools-version: 6.2
import PackageDescription

// world-atlas。WorldAtlasCore は依存なしの判断層で、ファイルも DB も触らない。
// WorldAtlasStore は GRDB の索引と監視を持ち、Core に依存する。
// WorldAtlasApp は画面で、Core と Store に依存する。swift test は GUI を起動しない。
let package = Package(
    name: "WorldAtlas",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "WorldAtlasCore", targets: ["WorldAtlasCore"]),
        .library(name: "WorldAtlasStore", targets: ["WorldAtlasStore"]),
        .executable(name: "WorldAtlasApp", targets: ["WorldAtlasApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.0.0"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.11.0"),
    ],
    targets: [
        .target(
            name: "WorldAtlasCore",
            dependencies: [.product(name: "Yams", package: "Yams")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "WorldAtlasStore",
            dependencies: [
                "WorldAtlasCore",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "WorldAtlasApp",
            dependencies: ["WorldAtlasCore", "WorldAtlasStore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "WorldAtlasCoreTests",
            dependencies: ["WorldAtlasCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "WorldAtlasStoreTests",
            dependencies: ["WorldAtlasStore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
