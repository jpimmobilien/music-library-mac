// swift-tools-version:5.9
// Panora – Kernlogik als Swift-Paket (ohne Apple-Frameworks, läuft auch unter Linux in der CI).
// Die App selbst (Sources/Panora) baut das Xcode-Projekt aus project.yml, weil MLX seine
// Metal-Shader nur mit xcodebuild übersetzen kann.
import PackageDescription

let package = Package(
    name: "Panora",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PanoraCore", targets: ["PanoraCore"]),
    ],
    targets: [
        .target(name: "PanoraCore", path: "Sources/PanoraCore"),
        .testTarget(name: "PanoraCoreTests", dependencies: ["PanoraCore"], path: "Tests/PanoraCoreTests"),
    ]
)
