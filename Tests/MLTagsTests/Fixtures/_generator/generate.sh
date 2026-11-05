#!/usr/bin/env bash
# Generates the MLTags test fixtures (≈1 s tones, tiny bit rates) into <out-dir>.
#
#   generate.sh <out-dir> <fixturetool-binary>
#
# Requirements: ffmpeg (libmp3lame, aac, alac, flac, libvorbis, libopus, libspeex, wmav2,
# wavpack, tta encoders), python3, and the fixturetool binary built from fixturetool.cpp
# against the vendored TagLib (see README in this folder).
# All content is generated here, so there are no licensing questions.
set -euo pipefail

OUT="$1"
TOOL="$2"
HERE="$(cd "$(dirname "$0")" && pwd)"
RAW="python3 -I $HERE/rawtool.py"
mkdir -p "$OUT"
cd "$OUT"
rm -f ./*.mp3 ./*.m4a ./*.flac ./*.ogg ./*.opus ./*.spx ./*.oga ./*.wav ./*.aiff ./*.wma ./*.wv ./*.tta ./*.dsf ./*.dff ./*.png ./*.jpg

FF=(ffmpeg -nostdin -hide_banner -loglevel error -y)
SINE=(-f lavfi -i sine=frequency=440:duration=1:sample_rate=8000)
SINE22=(-f lavfi -i sine=frequency=440:duration=1:sample_rate=22050)
COVER=(-map 0:a -map 1:v -c:v copy -disposition:v attached_pic)

# covers: 16x16 PNG and JPEG
"${FF[@]}" -f lavfi -i "color=c=0xC03020:s=16x16" -frames:v 1 cover.png
"${FF[@]}" -f lavfi -i "color=c=0x2040C0:s=16x16" -frames:v 1 -q:v 8 cover.jpg

meta() {
  META=(-metadata "title=Fixture Title" -metadata "artist=Fixture Artist" -metadata "album=Fixture Album"
        -metadata "album_artist=Fixture Album Artist" -metadata "composer=Fixture Composer"
        -metadata "genre=Rock" -metadata "date=2021-03-04" -metadata "track=3/12" -metadata "disc=1/2"
        -metadata "comment=Fixture comment" -metadata "MLTEST_CUSTOM=MLTEST-MARKER-$1-CUSTOM")
}

# MP3, ID3v2.3 + ID3v1, cover via ffmpeg
meta mp3v23
"${FF[@]}" "${SINE[@]}" -i cover.jpg "${COVER[@]}" -c:a libmp3lame -b:a 8k -ac 1 -id3v2_version 3 -write_id3v1 1 "${META[@]}" id3v23.mp3
"$TOOL" mp3v23 id3v23.mp3 cover.png cover.jpg MLTEST-MARKER-mp3v23

# MP3, ID3v2.4 + APE, cover via ffmpeg
meta mp3v24
"${FF[@]}" "${SINE[@]}" -i cover.png "${COVER[@]}" -c:a libmp3lame -b:a 8k -ac 1 -id3v2_version 4 "${META[@]}" id3v24.mp3
"$TOOL" mp3v24 id3v24.mp3 cover.png cover.jpg MLTEST-MARKER-mp3v24

# MPEG-4: AAC and ALAC
meta aac
"${FF[@]}" "${SINE22[@]}" -i cover.jpg "${COVER[@]}" -c:a aac -b:a 16k -ac 1 "${META[@]}" aac.m4a
"$TOOL" m4a aac.m4a cover.png cover.jpg MLTEST-MARKER-aac
meta alac
"${FF[@]}" "${SINE[@]}" -i cover.png "${COVER[@]}" -c:a alac -ac 1 "${META[@]}" alac.m4a
"$TOOL" m4a alac.m4a cover.png cover.jpg MLTEST-MARKER-alac

# FLAC (Vorbis Comment + picture block via ffmpeg, unknown APPLICATION block)
meta flac
"${FF[@]}" "${SINE[@]}" -i cover.png "${COVER[@]}" -c:a flac -ac 1 "${META[@]}" flac.flac
$RAW flacapp flac.flac MLTEST-MARKER-flac-APPLICATION

# Ogg Vorbis / Opus / Speex / FLAC (covers added as METADATA_BLOCK_PICTURE)
meta ogg
"${FF[@]}" "${SINE22[@]}" -c:a libvorbis -q:a 0 -ac 1 "${META[@]}" vorbis.ogg
"$TOOL" ogg vorbis.ogg cover.png cover.jpg MLTEST-MARKER-ogg
meta opus
"${FF[@]}" "${SINE[@]}" -c:a libopus -b:a 8k -ac 1 "${META[@]}" opus.opus
"$TOOL" opus opus.opus cover.png cover.jpg MLTEST-MARKER-opus
meta spx
"${FF[@]}" "${SINE[@]}" -c:a libspeex -ac 1 "${META[@]}" speex.spx
"$TOOL" spx speex.spx cover.png cover.jpg MLTEST-MARKER-spx
meta oga
"${FF[@]}" "${SINE[@]}" -c:a flac -ac 1 -f ogg "${META[@]}" oggflac.oga
"$TOOL" oga oggflac.oga cover.png cover.jpg MLTEST-MARKER-oga

# WAV: RIFF INFO from ffmpeg, ID3v2.3 chunk + cover from the tool, unknown chunk
meta wav
"${FF[@]}" "${SINE[@]}" -c:a pcm_s16le -ac 1 "${META[@]}" wave.wav
"$TOOL" wav wave.wav cover.png cover.jpg MLTEST-MARKER-wav
$RAW riffchunk wave.wav mlts MLTEST-MARKER-wav-CHUNK

# AIFF: ID3v2.4 chunk + cover from ffmpeg, unknown chunk
meta aiff
"${FF[@]}" "${SINE[@]}" -i cover.png "${COVER[@]}" -c:a pcm_s16be -ac 1 -write_id3v2 1 -id3v2_version 4 "${META[@]}" aiff.aiff
"$TOOL" aiff aiff.aiff cover.png cover.jpg MLTEST-MARKER-aiff
$RAW aiffchunk aiff.aiff MLTS MLTEST-MARKER-aiff-CHUNK

# WMA (ASF), cover from the tool
meta wma
"${FF[@]}" "${SINE[@]}" -c:a wmav2 -b:a 24k -ac 1 "${META[@]}" wma.wma
"$TOOL" wma wma.wma cover.png cover.jpg MLTEST-MARKER-wma

# WavPack (APEv2 from ffmpeg), cover from the tool
meta wv
"${FF[@]}" "${SINE[@]}" -c:a wavpack -ac 1 "${META[@]}" wavpack.wv
"$TOOL" wv wavpack.wv cover.png cover.jpg MLTEST-MARKER-wv

# TrueAudio, ID3v2 from the tool
"${FF[@]}" "${SINE[@]}" -c:a tta -ac 1 -map_metadata -1 tta.tta
"$TOOL" tta tta.tta cover.png cover.jpg MLTEST-MARKER-tta

# DSD: DSF and DSDIFF written byte by byte, ID3v2 from the tool
$RAW dsf dsd.dsf
"$TOOL" dsf dsd.dsf cover.png cover.jpg MLTEST-MARKER-dsf
$RAW dff dsd.dff
"$TOOL" dff dsd.dff cover.png cover.jpg MLTEST-MARKER-dff

ls -l "$OUT"
du -ch "$OUT"/* | tail -1
