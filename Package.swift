// swift-tools-version:5.9
//
// Music Library für macOS – Swift-Paket.
//
// Aufbau (siehe docs/ARCHITEKTUR.md):
//   MLCore     reine Logik ohne Apple-Frameworks (Modelle, Sortierung, Gruppierung, Smart-Playlists,
//              Duplikate, Wiedergaberegeln, Equalizer-Modell, Liedtext-Parser) – auch unter Linux testbar
//   MLStore    SQLite-Datenbank (Bibliothek, Playlists, Favoriten, Statistik, Verlauf, Journal)
//   TagBridge  TagLib 2.3.2 (C++) mit schmaler C-Schnittstelle
//   MLTags     Lesen/Schreiben der Tags in Swift + sichere Schreibstrategie (Sicherung, Kopie, Prüfung, Ersetzen, Rückgängig)
//   MLRender   Raster-Renderer der Player-Designs (Vinyl, Kassette, CD) – Portierung der Android-Renderer
//   OggVorbis  Ogg-Vorbis-Decoder (stb_vorbis), da macOS Ogg nicht selbst abspielt
//   MusicLibrary  die macOS-App (SwiftUI + AppKit + AVFoundation), nur unter macOS
//
import PackageDescription

// Header search paths of the vendored TagLib 2.3.2 (see Sources/TagBridge/README.md).
// "config" holds the hand-written replacements for TagLib's CMake-generated config headers.
let taglibDirs = [
    "config",
    "taglib", "taglib/toolkit", "taglib/ape", "taglib/asf", "taglib/dsdiff", "taglib/dsf", "taglib/flac",
    "taglib/it", "taglib/matroska", "taglib/matroska/ebml", "taglib/mod", "taglib/mp4", "taglib/mpc",
    "taglib/mpeg", "taglib/mpeg/id3v1", "taglib/mpeg/id3v2", "taglib/mpeg/id3v2/frames", "taglib/ogg",
    "taglib/ogg/flac", "taglib/ogg/opus", "taglib/ogg/speex", "taglib/ogg/vorbis", "taglib/riff",
    "taglib/riff/aiff", "taglib/riff/wav", "taglib/s3m", "taglib/shorten", "taglib/trueaudio",
    "taglib/wavpack", "taglib/xm", "utfcpp/source", "bridge",
]

var targets: [Target] = [
    .systemLibrary(name: "CSQLite", path: "Sources/CSQLite"),
    .target(
        name: "TagBridge",
        path: "Sources/TagBridge",
        exclude: [
            "LICENSE-TagLib.txt", "README.md", "MAPPING.md", "utfcpp/LICENSE",
            // template implementations, included by tlist.h / tmap.h
            "taglib/toolkit/tlist.tcc", "taglib/toolkit/tmap.tcc",
        ],
        publicHeadersPath: "include",
        cxxSettings: taglibDirs.map { .headerSearchPath($0) } + [
            .define("HAVE_CONFIG_H"),
            .define("TAGLIB_STATIC"),
            .define("NDEBUG"),
            .unsafeFlags(["-w"]),
        ],
        linkerSettings: [.linkedLibrary("z")]
    ),
    // Ogg-Vorbis-Decoder (stb_vorbis v1.22, MIT/Public Domain) – macOS kann Ogg nicht selbst abspielen
    .target(
        name: "CVorbis",
        path: "Sources/CVorbis",
        exclude: ["vendor"],
        cSettings: [.unsafeFlags(["-w"])]
    ),
    .target(name: "OggVorbis", dependencies: ["CVorbis"], path: "Sources/OggVorbis"),
    .target(name: "MLCore", path: "Sources/MLCore"),
    .target(name: "MLStore", dependencies: ["MLCore", "CSQLite"], path: "Sources/MLStore"),
    .target(name: "MLTags", dependencies: ["MLCore", "TagBridge"], path: "Sources/MLTags"),
    .target(name: "MLRender", path: "Sources/MLRender"),
    .testTarget(name: "MLCoreTests", dependencies: ["MLCore"], path: "Tests/MLCoreTests"),
    .testTarget(name: "MLStoreTests", dependencies: ["MLStore"], path: "Tests/MLStoreTests"),
    .testTarget(
        name: "MLTagsTests",
        dependencies: ["MLTags"],
        path: "Tests/MLTagsTests",
        resources: [.copy("Fixtures")]
    ),
    .testTarget(name: "MLRenderTests", dependencies: ["MLRender"], path: "Tests/MLRenderTests"),
    .testTarget(name: "OggVorbisTests", dependencies: ["OggVorbis"], path: "Tests/OggVorbisTests", resources: [.copy("Fixtures")]),
]

#if os(macOS)
targets.append(
    .executableTarget(
        name: "MusicLibrary",
        dependencies: ["MLCore", "MLStore", "MLTags", "MLRender", "OggVorbis"],
        path: "Sources/MusicLibrary",
        linkerSettings: [
            .linkedFramework("AppKit"),
            .linkedFramework("AVFoundation"),
            .linkedFramework("AudioToolbox"),
            .linkedFramework("MediaPlayer"),
            .linkedFramework("Accelerate"),
            .linkedFramework("UniformTypeIdentifiers"),
            .linkedFramework("iTunesLibrary"),
        ]
    )
)
targets.append(
    .testTarget(name: "MusicLibraryTests", dependencies: ["MusicLibrary"], path: "Tests/MusicLibraryTests")
)
#endif

let package = Package(
    name: "MusicLibrary",
    defaultLocalization: "de",
    platforms: [.macOS(.v13)],
    targets: targets,
    cxxLanguageStandard: .cxx17
)
