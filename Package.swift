// swift-tools-version: 6.2
import PackageDescription

// world-atlas。WorldAtlasCore は依存なしの判断層で、ファイルも DB も触らない。
// WorldAtlasStore は GRDB の索引と監視を持ち、Core に依存する。
// WorldAtlasUI は画面と、画面のための判断を持つ。WorldAtlasApp は @main だけである。
// swift test は GUI を起動しない。
let package = Package(
    name: "WorldAtlas",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "WorldAtlasCore", targets: ["WorldAtlasCore"]),
        .library(name: "WorldAtlasStore", targets: ["WorldAtlasStore"]),
        .library(name: "WorldAtlasUI", targets: ["WorldAtlasUI"]),
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
        .target(
            name: "WorldAtlasUI",
            dependencies: ["WorldAtlasCore", "WorldAtlasStore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "WorldAtlasApp",
            dependencies: ["WorldAtlasUI"],
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
        .testTarget(
            name: "WorldAtlasUITests",
            dependencies: ["WorldAtlasUI", "WorldAtlasStore", "WorldAtlasCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
