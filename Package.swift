// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AstroNatalEngine",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "AstroNatalEngine",
            targets: ["AstroNatalEngine"]
        )
    ],
    targets: [
        .target(
            name: "AstroSchemas"
        ),
        .target(
            name: "AstroTime",
            dependencies: ["AstroSchemas"]
        ),
        .target(
            name: "AstroFrames",
            dependencies: [
                "AstroSchemas",
                "AstroTime"
            ]
        ),
        .target(
            name: "AstroHouses",
            dependencies: ["AstroSchemas"]
        ),
        .target(
            name: "AstroNatal",
            dependencies: ["AstroSchemas"]
        ),
        .target(
            name: "AstroRuntimeData",
            dependencies: ["AstroSchemas"]
        ),
        .target(
            name: "AstroEphemeris",
            dependencies: ["AstroSchemas"]
        ),
        .target(
            name: "AstroNatalEngine",
            dependencies: [
                "AstroSchemas",
                "AstroTime",
                "AstroFrames",
                "AstroHouses",
                "AstroNatal",
                "AstroRuntimeData",
                "AstroEphemeris"
            ]
        ),
        .testTarget(
            name: "AstroSchemasTests",
            dependencies: ["AstroSchemas"]
        ),
        .testTarget(
            name: "AstroTimeTests",
            dependencies: [
                "AstroTime",
                "AstroSchemas"
            ]
        ),
        .testTarget(
            name: "AstroFramesTests",
            dependencies: [
                "AstroFrames",
                "AstroSchemas",
                "AstroTime"
            ]
        ),
        .testTarget(
            name: "AstroHousesTests",
            dependencies: [
                "AstroHouses",
                "AstroSchemas"
            ]
        ),
        .testTarget(
            name: "AstroNatalTests",
            dependencies: [
                "AstroNatal",
                "AstroSchemas"
            ]
        ),
        .testTarget(
            name: "AstroRuntimeDataTests",
            dependencies: [
                "AstroRuntimeData",
                "AstroSchemas"
            ]
        ),
        .testTarget(
            name: "AstroEphemerisTests",
            dependencies: [
                "AstroEphemeris",
                "AstroSchemas"
            ]
        ),
        .testTarget(
            name: "AstroNatalEngineTests",
            dependencies: [
                "AstroNatalEngine",
                "AstroSchemas",
                "AstroRuntimeData",
                "AstroEphemeris"
            ]
        )
    ]
)
