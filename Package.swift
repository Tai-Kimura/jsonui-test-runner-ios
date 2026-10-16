// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "JsonUITestRunner",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "JsonUITestRunner",
            targets: ["JsonUITestRunner"]
        ),
    ],
    targets: [
        .target(
            name: "JsonUITestRunner",
            dependencies: [],
            path: "Sources/JsonUITestRunner"
        ),
        .testTarget(
            name: "JsonUITestRunnerTests",
            dependencies: ["JsonUITestRunner"],
            path: "Tests/JsonUITestRunnerTests",
            // Byte-identical copies of jsonui-test-runner specs/vectors/
            // (initial-state-payload.json, state-path.json): the shared
            // vectors this driver must pass.
            resources: [.copy("Fixtures")]
        ),
    ]
)
