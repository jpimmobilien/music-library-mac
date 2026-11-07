// swift-tools-version:5.9
//
// PROJECT AETHER – macOS Edition · System Intelligence & File Explorer
//
//   AetherCore    reine Swift-Logik ohne Apple-Frameworks: Messwert-Herkunft, CPU-/Speicher-/Raten-Mathematik,
//                 Puls-Regeln, Formatierung, Theme-Paletten (mit Kontrastprüfung), Parser. Auch unter Linux getestet.
//   AetherSystem  nur macOS: Messquellen über Darwin, IOKit, Metal, IOPowerSources – je mit Fähigkeitserkennung.
//   AETHER        die App (SwiftUI + AppKit), nur macOS.
//
// Universal Binary: scripts/build_app.sh baut arm64 und x86_64 getrennt und führt sie mit lipo zusammen.
import PackageDescription

var targets: [Target] = [
    .target(name: "AetherCore", path: "Sources/AetherCore"),
    .testTarget(name: "AetherCoreTests", dependencies: ["AetherCore"], path: "Tests/AetherCoreTests"),
]

var products: [Product] = [.library(name: "AetherCore", targets: ["AetherCore"])]

#if os(macOS)
targets.append(
    .target(
        name: "AetherSystem",
        dependencies: ["AetherCore"],
        path: "Sources/AetherSystem",
        linkerSettings: [
            .linkedFramework("IOKit"),
            .linkedFramework("Metal"),
            .linkedFramework("CoreFoundation"),
        ]
    )
)
targets.append(
    .executableTarget(
        name: "AETHER",
        dependencies: ["AetherCore", "AetherSystem"],
        path: "Sources/AETHER",
        linkerSettings: [
            .linkedFramework("AppKit"),
            .linkedFramework("SwiftUI"),
        ]
    )
)
products.append(.executable(name: "AETHER", targets: ["AETHER"]))
#endif

let package = Package(
    name: "AETHER",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: products,
    targets: targets
)
