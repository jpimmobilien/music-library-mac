# TagBridge

TagLib 2.3.2 (C++) with a small pure-C interface for Swift (`include/TagBridge.h`).

| | |
|---|---|
| TagLib version | 2.3.2 (tag `v2.3.2`, commit `deadc2990767dfbda0701e0ab35fdeea653db08f`) |
| utfcpp | commit `2d8e20b22dcb3e9b3c4f52103182ebda949c6089` (TagLib's `3rdparty/utfcpp` submodule) |
| License | TagLib: MPL 1.1 (dual LGPL 2.1 / MPL 1.1, used under MPL 1.1), utfcpp: BSL 1.0 – see `LICENSE-TagLib.txt`, `utfcpp/LICENSE` |
| Field mapping | `MAPPING.md` |

## Layout

```
include/TagBridge.h      public C header (the only header visible to Swift)
bridge/TagBridge.cpp     implementation of the C API on top of TagLib
config/config.h          hand-written replacement for TagLib's CMake-generated config.h
config/taglib_config.h   hand-written replacement for taglib_config.h (all formats enabled)
taglib/…                 TagLib 2.3.2 sources and headers, UNMODIFIED (only *.h, *.cpp, *.tcc copied)
utfcpp/source/…          utfcpp headers, UNMODIFIED
```

Not vendored: TagLib's CMake files, docs, examples, bindings, tests and the ID3/APE
specification text files.

## How it is built

Plain SwiftPM, no CMake and no generated files at build time:

* SwiftPM compiles every `.cpp` under `Sources/TagBridge` (TagLib + bridge) as C++17
  (`cxxLanguageStandard: .cxx17` in `Package.swift`).
* `taglibDirs` in `Package.swift` lists all TagLib header directories plus `config`,
  `utfcpp/source` and `bridge`; each becomes a `headerSearchPath`.
* Defines: `HAVE_CONFIG_H` (TagLib includes `config.h`), `TAGLIB_STATIC`, `NDEBUG`
  (TagLib debug output off); `-w` silences warnings of the third-party code.
* `config.h`: `HAVE_GCC_BYTESWAP` (clang/gcc builtins, valid for arm64 and x86_64) and
  `HAVE_ZLIB` (compressed ID3v2 frames); zlib is linked with `.linkedLibrary("z")`
  (`libz.tbd` in the macOS SDK, `zlib1g-dev` on Linux).
* `taglib/toolkit/tlist.tcc`, `tmap.tcc` (template implementations included by headers),
  this README, `MAPPING.md`, `LICENSE-TagLib.txt` and `utfcpp/LICENSE` are excluded from
  compilation in the target definition.
* Byte order is determined at compile time by TagLib itself, so one source tree serves a
  universal (arm64 + x86_64) build. Deployment target macOS 13 is sufficient (C++17).

Updating TagLib: replace `taglib/` and `utfcpp/source/` with the new release (only
`*.h`, `*.cpp`, `*.tcc`), compare `config.h.cmake` / `taglib/taglib_config.h.cmake` and
`taglib/CMakeLists.txt` (new directories → `taglibDirs`, new `.tcc` → `exclude`), then run the
MLTags tests.

## C API in short

Open with `tb_open(path, flags, &file)`, query `tb_file_type`, `tb_tag_types`,
`tb_id3v2_version`, `tb_audio_properties`, read/write fields with
`tb_get_strings`/`tb_set_strings` (text, multi-values as lists) and `tb_get_int`/`tb_set_int`
(year, track/disc number and total, compilation, rating 0…100, BPM), pictures with
`tb_get_pictures`/`tb_set_pictures`/`tb_add_picture`/`tb_remove_picture`/`tb_replace_picture`,
TagLib properties with `tb_get_property*`/`tb_set_property`, then `tb_save` and `tb_close`.
Every call returns a `TBStatus`; `tb_last_error(file)` has the message. Lists returned by the
bridge are freed with `tb_string_list_free` / `tb_picture_list_free`. No C++ exception crosses
the interface.
