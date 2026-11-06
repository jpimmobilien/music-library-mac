// swift-tools-version:5.9
//
// Android Bridge – native Android-zu-Mac-Dateiübertragung über USB (MTP).
//
//   ABCore         reine Logik ohne Apple-Frameworks: PTP/MTP-Container, Datensätze, Datumsformat,
//                  Geräteklassifizierung, Konfliktnamen, Sortierung, Filter, Übertragungsmathematik.
//                  Auch unter Linux testbar.
//   AndroidBridge  die macOS-App (SwiftUI + AppKit + IOKit/IOUSBHost), nur unter macOS.
//
import PackageDescription

var targets: [Target] = [
    .target(name: "ABCore", path: "Sources/ABCore"),
    .testTarget(name: "ABCoreTests", dependencies: ["ABCore"], path: "Tests/ABCoreTests"),
]

#if os(macOS)
// Abfangen von Objective-C-Ausnahmen aus IOUSBHost (Swift kann das nicht selbst)
targets.append(.target(name: "ABObjC", path: "Sources/ABObjC"))
targets.append(
    .executableTarget(
        name: "AndroidBridge",
        dependencies: ["ABCore", "ABObjC"],
        path: "Sources/AndroidBridge",
        linkerSettings: [
            .linkedFramework("AppKit"),
            .linkedFramework("IOKit"),
            .linkedFramework("IOUSBHost"),
            .linkedFramework("QuickLookThumbnailing"),
            .linkedFramework("UserNotifications"),
            .linkedFramework("ServiceManagement"),
        ]
    )
)
#endif

let package = Package(
    name: "AndroidBridge",
    platforms: [.macOS(.v13)],
    products: {
        var p: [Product] = [.library(name: "ABCore", targets: ["ABCore"])]
        #if os(macOS)
        p.append(.executable(name: "AndroidBridge", targets: ["AndroidBridge"]))
        #endif
        return p
    }(),
    targets: targets
)
