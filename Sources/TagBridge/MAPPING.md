# Tag mapping (TagBridge / MLTags)

How the fields of `TagValues` are stored per tag format. Implemented in
`Sources/TagBridge/bridge/TagBridge.cpp`; normalisation and verification in `Sources/MLTags`.

## Formats

| File type | Primary tag (read + write) | Secondary tags (kept, updated for edited fields, read as fallback) | Pictures |
|---|---|---|---|
| MP3 / MP2 / ADTS-AAC | ID3v2 (version kept: 2.3 stays 2.3, 2.4 stays 2.4, 2.2 is written as 2.3, new tag = 2.4) | ID3v1, APEv2 (only if already present) | ID3v2 APIC |
| MP4 / M4A / M4B / ALAC | iTunes `ilst` atoms | – | `covr` list |
| FLAC | Vorbis Comment | ID3v2 (written as 2.4 by TagLib), ID3v1 (only if present) | FLAC PICTURE blocks |
| Ogg Vorbis / Opus / Speex / FLAC | Vorbis Comment | – | `METADATA_BLOCK_PICTURE` |
| WAV | ID3v2 chunk (`ID3 `) | RIFF `LIST/INFO` (only if present) | ID3v2 APIC |
| AIFF / AIFC | ID3v2 chunk | – | ID3v2 APIC |
| DSF | ID3v2 | – | ID3v2 APIC |
| DSDIFF | ID3v2 | DIIN (title/artist, only if present) | ID3v2 APIC |
| TrueAudio | ID3v2 (always written as 2.4 by TagLib) | ID3v1 (only if present) | ID3v2 APIC |
| APE / WavPack / Musepack | APEv2 | ID3v1 (only if present) | `Cover Art (…)` items, one per type |
| WMA / ASF | ASF content description + extended attributes | – | `WM/Picture` |
| Matroska, Shorten, MOD/S3M/IT/XM | TagLib PropertyMap | – | read-only |

Tag types that exist in a file are never removed: saving keeps every tag type that was present
(`StripNone`, no duplication between tags). A secondary tag is updated with the values of the
edited fields it can hold, so a fallback read never returns stale data. Exception: a tag that
becomes completely empty because all of its fields were cleared is dropped by TagLib (e.g. the
ID3v1 tag after clearing title/artist/album/year/comment/track/genre). Note that ffmpeg's MP3
gapless trimming reacts to a trailing ID3v1 tag, so the PCM ffmpeg decodes from such a file can
differ by the encoder padding although the MPEG frames are byte-identical.

## Fields

| Field | ID3v2 | MP4 | Vorbis Comment | APEv2 | ASF (WMA) | RIFF INFO (secondary) |
|---|---|---|---|---|---|---|
| title | TIT2 | ©nam | TITLE | Title | Title (content descr.) | INAM |
| artists * | TPE1 | ©ART | ARTIST | Artist | Author (content descr.) | IART |
| album | TALB | ©alb | ALBUM | Album | WM/AlbumTitle | IPRD |
| albumArtists * | TPE2 | aART | ALBUMARTIST (+ALBUM ARTIST, ALBUM_ARTIST) | Album Artist (+AlbumArtist, Album_Artist) | WM/AlbumArtist | – |
| composers * | TCOM | ©wrt | COMPOSER | Composer | WM/Composer | IMUS |
| grouping | GRP1, TIT1 (see below) | ©grp | GROUPING | Grouping | WM/ContentGroupDescription | – |
| work | TIT1 or TXXX:WORK (see below) | ©wrk | WORK | Work | – (not supported) | – |
| genres * | TCON (ID3v1 numbers resolved) | ©gen (gnre read) | GENRE | Genre | WM/Genre | IGNR |
| year / date | TDRC (v2.3: TYER/TDAT/TIME; TYER also read in v2.4) | ©day | DATE (+YEAR) | Year (+Date) | WM/Year | ICRD |
| trackNumber / trackTotal | TRCK `n/t` | trkn | TRACKNUMBER + TRACKTOTAL (+TOTALTRACKS; `n/t` in TRACKNUMBER read) | Track `n/t` | WM/TrackNumber (no total) | IPRT (+ITRK) |
| discNumber / discTotal | TPOS `n/t` | disk | DISCNUMBER + DISCTOTAL (+TOTALDISCS) | Disc `n/t` | WM/PartOfSet `n/t` | – |
| compilation | TCMP = 1 | cpil | COMPILATION = 1 | Compilation = 1 | – (not supported) | – |
| rating (0…100) | POPM (see below) | ----:com.apple.iTunes:RATING (0…100) | RATING (0…100; FMPS_RATING read/updated) | Rating (0…100) | WM/SharedUserRating (0/1/25/50/75/99) | – |
| bpm | TBPM | tmpo | BPM | BPM | WM/BeatsPerMinute | – |
| comment | COMM without description (+TXXX:COMMENT as written by ffmpeg) | ©cmt | COMMENT (+DESCRIPTION) | Comment | Description (content descr.; +attribute „Description“ as written by ffmpeg) | ICMT |
| lyrics | USLT | ©lyr | LYRICS (+UNSYNCEDLYRICS) | Lyrics (+UnsyncedLyrics) | WM/Lyrics | – |
| titleSort | TSOT | sonm | TITLESORT | TITLESORT | WM/TitleSortOrder | – |
| artistSort | TSOP | soar | ARTISTSORT | ARTISTSORT | WM/ArtistSortOrder | – |
| albumSort | TSOA | soal | ALBUMSORT | ALBUMSORT | WM/AlbumSortOrder | – |
| albumArtistSort | TSO2 | soaa | ALBUMARTISTSORT | ALBUMARTISTSORT | WM/AlbumArtistSortOrder | – |
| composerSort | TSOC | soco | COMPOSERSORT | COMPOSERSORT | – (not supported) | – |
| copyright | TCOP | cprt | COPYRIGHT | Copyright | Copyright (content descr.) | ICOP |
| publisher (label) | TPUB | ----:com.apple.iTunes:LABEL (+©pub) | LABEL (+ORGANIZATION, PUBLISHER) | Label (+Publisher) | WM/Publisher | – |
| isrc | TSRC | ----:com.apple.iTunes:ISRC | ISRC | ISRC | WM/ISRC | – |
| encodedBy | TENC | ©enc | ENCODEDBY (+ENCODED-BY) | EncodedBy (+Encoded By) | WM/EncodedBy | – |

ID3v1 (secondary): title, artist, album, year, comment, track number, genre (first value).
DIIN (secondary): title, artist.

Keys in parentheses are **aliases**: they are read when the first key is empty and, if they
already exist in the file, they are updated (or removed) together with the first key. New
values are always written to the first key.

### Multi-valued fields (*)

`artists`, `albumArtists`, `composers`, `genres`:

* ID3v2.4: one frame with NUL-separated values.
* ID3v2.3 (no official multi-value support): one value, joined with `"; "`.
* Vorbis Comment: one field per value (`ARTIST=A`, `ARTIST=B`).
* APEv2: one item with NUL-separated values.
* MP4: one string joined with `"; "` (iTunes reads only the first `data` atom of an item).
* ASF: one attribute joined with `"; "` (TagLib does not keep the order of repeated attributes).
* RIFF INFO / ID3v1: joined with `"; "`.

Reading splits every value at `;` and trims, so `"A; B"` and two separate values `A`, `B`
are both read as `["A", "B"]` (consistent with `TagValues.setText`).

### Grouping and work in ID3v2

iTunes ≥ 12.5 writes grouping to `GRP1` and work to `TIT1`; older software writes grouping to
`TIT1`. Rules:

* **Read grouping:** `GRP1`, else `TIT1`.
* `TIT1` counts as *used for grouping* if there is no `GRP1` or `TIT1` equals `GRP1`.
* **Read work:** `TXXX:WORK`, else `TIT1` if it is not used for grouping.
* **Write grouping:** `GRP1` is set. An existing `TIT1` that held the old grouping value is
  updated too (legacy readers keep working); in that case the work is stored in `TXXX:WORK`.
* **Write work:** `TIT1` (iTunes) when a grouping exists in `GRP1`; without a grouping the work
  goes to `TXXX:WORK` (a lone `TIT1` would be read as grouping by older software). If the
  work equals the grouping, `TXXX:WORK` is written as well.
* Writing one of the two never changes the value read for the other.

Limitation: a file written by iTunes that has only a work (`TIT1`) and no grouping is read as
grouping = work text (ambiguous by design of the formats).

### Rating

`TagValues.rating` is 0…100 (20 per star). 0 is treated like "no rating" (the field is removed).

* **ID3v2 POPM** (byte 1…255). Written values (Windows Media Player for full stars,
  MediaMonkey/MusicBee for half stars):

  | stars | ½ | 1 | 1½ | 2 | 2½ | 3 | 3½ | 4 | 4½ | 5 |
  |---|---|---|---|---|---|---|---|---|---|---|
  | rating | 10 | 20 | 30 | 40 | 50 | 60 | 70 | 80 | 90 | 100 |
  | POPM | 13 | 1 | 54 | 64 | 118 | 128 | 186 | 196 | 242 | 255 |

  Ratings between the steps are rounded to the nearest half star (`(r + 5) / 10`). Reading:
  the values above exactly, otherwise the WMP ranges 1–31 → 20, 32–95 → 40, 96–159 → 60,
  160–223 → 80, 224–255 → 100. The POPM frame with e-mail `Windows Media Player 9 Series` is
  preferred, otherwise the first one with a rating. Writing updates the rating byte of **all**
  existing POPM frames (their e-mail and play counter stay unchanged); if there is none, a
  frame with the WMP e-mail and counter 0 is added. Removing the rating deletes POPM frames
  without play counter and sets the rating byte to 0 in frames with a counter.
* **MP4:** freeform `----:com.apple.iTunes:RATING` as text 0…100 (not `rtng`, which is the
  content advisory flag). Apple Music itself does not store ratings in files.
* **Vorbis Comment / APE:** `RATING` 0…100 (other apps may use 1…5 – not detectable).
* **ASF:** `WM/SharedUserRating` only knows full stars (1, 25, 50, 75, 99); half stars are
  rounded to full stars.

### Other rules

* **Year:** read from the date (`2024-05-17` → 2024). Writing a year keeps an existing full
  date whose year is equal; otherwise the date becomes the year only.
* **Track/disc:** number and total are written together (`n/t`, `trkn`, separate keys);
  writing one keeps the other. A total without a number is stored as `0/t`; 0 reads as "none".
  Range 1…32767 (MP4 stores 16-bit values).
* **Comment (ID3v2):** only `COMM` frames **without** description are the comment; frames like
  `iTunNORM`, `iTunSMPB` are never touched. An existing frame keeps its language; new frames use
  `eng`.
* **Lyrics (ID3v2):** the first `USLT` frame is updated (language and description kept); a new
  frame uses language `und`. Removing the lyrics removes all `USLT` frames. `SYLT` is not touched.
* **Text encoding (ID3v2):** ASCII → ISO-8859-1, otherwise UTF-8 (v2.4) / UTF-16 (v2.3).
* **Compilation:** `false` removes the field.
* **Pictures:** written as given (type, MIME, description, data, and – for FLAC/Vorbis – width,
  height, colour depth from `ImageProbe`). MP4 `covr` has no types or descriptions: all
  pictures are read as front cover, order is kept. APEv2 keeps one picture per type and stores
  no MIME type (it is detected from the data). WMA keeps the pictures but not their order.

## What is never lost

Before saving, the bridge checks that TagLib would not drop data; if it would, the file is
reported as not writable (`tb_writable_reason`):

* ID3v2: frames TagLib cannot write (ID3v2.2-only frames, `EQUA`, `RVAD`, `TRDA`, `TSIZ`),
  ID3v2.4-only frames in an ID3v2.3 tag (`TDRL`, `TMOO`, `TSST`, …), `TDAT`/`TIME` that could
  not be merged into the date.
* MP4: `ilst` atoms that TagLib cannot parse (unknown data types) or duplicates.
* Files whose type is not confirmed by the file header (except MP3 without junk at the start).

Unknown frames/atoms/fields/chunks/blocks (e.g. `PRIV`, unknown frame IDs, `©xyz`, custom
Vorbis/APE/ASF fields, unknown RIFF/AIFF chunks, FLAC APPLICATION blocks) are preserved; the
tests check this byte for byte with marker strings.

## Verification after writing (SafeTagWriter)

The temporary copy is re-read and compared with the expectation before it replaces the original:
every edited field (normalised as described above), all other fields, the pictures, the audio
properties (duration ±50 ms, sample rate, channels, codec, bit depth) and – byte for byte – the
audio payload (`tb_audio_payload_checksum`: CRC-32 + Adler-32 + length over everything that
belongs to the audio stream, see `TagBridge.h`). For WMA, the order of repeated values and
pictures is compared order-insensitively because TagLib does not preserve it.
