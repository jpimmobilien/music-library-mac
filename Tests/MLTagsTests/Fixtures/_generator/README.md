# Test fixtures

All files in `Fixtures/` are generated (1 s 440 Hz tone, mono, tiny bit rates; DSD files 0.05 s),
so there are no licensing questions. Each file carries the same initial tags
(`Fixture Title`, `Fixture Artist`, `Fixture Album`, genre `Rock`, date `2021-03-04`, track `3/12`,
disc `1/2`, comment `Fixture comment`), one embedded cover (16×16 PNG or JPEG) and marker strings
`MLTEST-MARKER-<format>-<kind>` in data that TagLib does not interpret (PRIV and unknown `XTST`
ID3v2 frames, custom TXXX/freeform/Vorbis/APE/ASF fields, the MP4 atom `©xyz`, an unknown RIFF/AIFF
chunk, a FLAC APPLICATION block). The tests check that these bytes survive every write.

| File | Container / codec | Tags as generated |
|---|---|---|
| id3v23.mp3 | MP3 (LAME 8 kbit/s) | ID3v2.3 + ID3v1, foreign POPM with play counter, iTunNORM COMM, USLT `deu` |
| id3v24.mp3 | MP3 | ID3v2.4 + APEv2, legacy grouping in TIT1 |
| aac.m4a / alac.m4a | MPEG-4 AAC / ALAC | iTunes atoms, covr |
| flac.flac | FLAC | Vorbis Comment, PICTURE block, APPLICATION block |
| vorbis.ogg, opus.opus, speex.spx, oggflac.oga | Ogg | Vorbis Comment + METADATA_BLOCK_PICTURE |
| wave.wav | WAV PCM | RIFF INFO (ffmpeg) + ID3v2.3 chunk |
| aiff.aiff | AIFF PCM | ID3v2.4 chunk |
| wma.wma | ASF / WMA v2 | ASF attributes, WM/Picture |
| wavpack.wv | WavPack | APEv2 incl. `Cover Art (Front)` |
| tta.tta | TrueAudio | ID3v2.4 |
| dsd.dsf / dsd.dff | DSF / DSDIFF (DSD64) | ID3v2.4 |

Regenerate (needs ffmpeg with libmp3lame, libvorbis, libopus, libspeex; python3):

```sh
# build the helper against the vendored TagLib (objects from a SwiftPM build of TagBridge)
TB=Sources/TagBridge
INC=$(for d in config taglib $(cd $TB && find taglib -type d) utfcpp/source; do printf -- "-I$TB/%s " $d; done)
g++ -std=c++17 -DHAVE_CONFIG_H -DTAGLIB_STATIC $INC -o /tmp/fixturetool \
    Tests/MLTagsTests/Fixtures/_generator/fixturetool.cpp $(find .build/debug/TagBridge.build/taglib -name '*.o') -lz
Tests/MLTagsTests/Fixtures/_generator/generate.sh /tmp/fixtures /tmp/fixturetool
cp /tmp/fixtures/* Tests/MLTagsTests/Fixtures/
```

`fixturetool.cpp` uses TagLib's own C++ API (not the TagBridge C API that is under test) for the
parts ffmpeg cannot write; `rawtool.py` writes the DSD files and injects unknown chunks/blocks.
