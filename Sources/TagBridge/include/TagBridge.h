/*
 * TagBridge – a small, pure C interface to TagLib 2.3.2 for Swift.
 *
 * Rules of the interface
 *  - No C++ types and no C++ exceptions cross this boundary. Every function catches
 *    everything internally and reports failures as a TBStatus (plus a message that can
 *    be fetched with tb_last_error()).
 *  - Strings are NUL-terminated UTF-8 in both directions. Paths are UTF-8 file-system paths.
 *  - Memory returned by the bridge (TBStringList, TBPictureList, char *) is owned by the
 *    caller and must be released with the matching tb_*_free() function. Input pointers
 *    are only read during the call and are never retained.
 *  - A TBFile handle is not thread-safe; use one handle per thread. Different handles
 *    may be used concurrently.
 *  - Nothing is written to disk before tb_save() is called; all setters only change the
 *    in-memory tags of the handle.
 *
 * See Sources/TagBridge/MAPPING.md for the field mapping per tag format.
 */

#ifndef TAGBRIDGE_H
#define TAGBRIDGE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ---------------------------------------------------------------------------------- */
/* Status codes                                                                        */
/* ---------------------------------------------------------------------------------- */

typedef enum TBStatus {
    TB_OK = 0,
    TB_ERROR_INVALID_ARGUMENT = 1,   /* NULL pointer, unknown field, value out of range */
    TB_ERROR_FILE_NOT_FOUND = 2,     /* path does not exist */
    TB_ERROR_OPEN_FAILED = 3,        /* exists but cannot be opened (permissions, directory, I/O) */
    TB_ERROR_UNSUPPORTED_FORMAT = 4, /* no TagLib file type matches the file */
    TB_ERROR_INVALID_FILE = 5,       /* format recognised but the file could not be parsed */
    TB_ERROR_READ_ONLY = 6,          /* handle/file/format cannot be written */
    TB_ERROR_UNSUPPORTED_FIELD = 7,  /* the tag format of this file cannot store this field */
    TB_ERROR_SAVE_FAILED = 8,        /* TagLib reported a failure while saving */
    TB_ERROR_OUT_OF_MEMORY = 9,
    TB_ERROR_INTERNAL = 10           /* unexpected exception inside TagLib or the bridge */
} TBStatus;

/* ---------------------------------------------------------------------------------- */
/* File types, tag types                                                                */
/* ---------------------------------------------------------------------------------- */

typedef enum TBFileType {
    TB_FILE_UNKNOWN = 0,
    TB_FILE_MPEG = 1,        /* MP3 / MP2 / MP1 / ADTS-AAC */
    TB_FILE_MP4 = 2,         /* M4A / M4B / M4P / MP4 (AAC, ALAC, ...) */
    TB_FILE_FLAC = 3,
    TB_FILE_OGG_VORBIS = 4,
    TB_FILE_OGG_OPUS = 5,
    TB_FILE_OGG_SPEEX = 6,
    TB_FILE_OGG_FLAC = 7,
    TB_FILE_WAV = 8,
    TB_FILE_AIFF = 9,
    TB_FILE_APE = 10,        /* Monkey's Audio */
    TB_FILE_WAVPACK = 11,
    TB_FILE_MPC = 12,        /* Musepack */
    TB_FILE_ASF = 13,        /* WMA */
    TB_FILE_DSF = 14,
    TB_FILE_DSDIFF = 15,
    TB_FILE_TRUEAUDIO = 16,
    TB_FILE_MATROSKA = 17,
    TB_FILE_SHORTEN = 18,
    TB_FILE_MOD = 19         /* MOD / S3M / IT / XM tracker modules */
} TBFileType;

/* Bit mask of tag types present in the file (as found on disk when the handle was opened). */
enum {
    TB_TAG_ID3V1 = 1u << 0,
    TB_TAG_ID3V2 = 1u << 1,
    TB_TAG_APE = 1u << 2,
    TB_TAG_XIPH = 1u << 3,        /* Vorbis Comment (FLAC, Ogg) */
    TB_TAG_MP4 = 1u << 4,         /* iTunes-style ilst atoms */
    TB_TAG_ASF = 1u << 5,
    TB_TAG_RIFF_INFO = 1u << 6,
    TB_TAG_DIIN = 1u << 7,        /* DSDIFF edited master information */
    TB_TAG_MATROSKA = 1u << 8,
    TB_TAG_FLAC_PICTURE = 1u << 9,/* FLAC METADATA_BLOCK_PICTURE blocks */
    TB_TAG_OTHER = 1u << 31
};

/* ---------------------------------------------------------------------------------- */
/* Fields                                                                               */
/* ---------------------------------------------------------------------------------- */

/* Text fields are read/written with tb_get_strings()/tb_set_strings(),
 * numeric fields with tb_get_int()/tb_set_int(). */
typedef enum TBField {
    /* text (single value; several raw values may be returned if the file has them) */
    TB_FIELD_TITLE = 0,
    /* text, multi-valued (ID3v2.4, Vorbis Comment, APE, ASF: one value per entry;
     * ID3v2.3, MP4, RIFF INFO, ID3v1: values joined with "; " into one string) */
    TB_FIELD_ARTISTS = 1,
    TB_FIELD_ALBUM = 2,
    TB_FIELD_ALBUM_ARTISTS = 3,      /* multi-valued */
    TB_FIELD_COMPOSERS = 4,          /* multi-valued */
    TB_FIELD_GROUPING = 5,
    TB_FIELD_WORK = 6,
    TB_FIELD_GENRES = 7,             /* multi-valued */
    TB_FIELD_COMMENT = 8,
    TB_FIELD_LYRICS = 9,
    TB_FIELD_TITLE_SORT = 10,
    TB_FIELD_ARTIST_SORT = 11,
    TB_FIELD_ALBUM_SORT = 12,
    TB_FIELD_ALBUM_ARTIST_SORT = 13,
    TB_FIELD_COMPOSER_SORT = 14,
    TB_FIELD_COPYRIGHT = 15,
    TB_FIELD_PUBLISHER = 16,         /* record label */
    TB_FIELD_ISRC = 17,
    TB_FIELD_ENCODED_BY = 18,
    TB_FIELD_DATE = 19,              /* read-only: full date string as stored ("2024-05-17") */

    /* numeric */
    TB_FIELD_YEAR = 32,              /* writing keeps an existing full date if its year is equal */
    TB_FIELD_TRACK_NUMBER = 33,
    TB_FIELD_TRACK_TOTAL = 34,
    TB_FIELD_DISC_NUMBER = 35,
    TB_FIELD_DISC_TOTAL = 36,
    TB_FIELD_COMPILATION = 37,       /* 0 / 1 */
    TB_FIELD_RATING = 38,            /* 0...100 (20 per star) */
    TB_FIELD_BPM = 39
} TBField;

/* ---------------------------------------------------------------------------------- */
/* Data structures                                                                      */
/* ---------------------------------------------------------------------------------- */

typedef struct TBAudioProperties {
    int64_t durationMs;
    int32_t bitrateKbps;
    int32_t sampleRate;
    int32_t channels;
    int32_t bitsPerSample;     /* 0 if not applicable/unknown (lossy codecs) */
    char codec[32];            /* "MP3", "AAC", "ALAC", "FLAC", "Vorbis", "Opus", "PCM", ... */
} TBAudioProperties;

typedef struct TBStringList {
    size_t count;
    char **items;              /* count UTF-8 strings */
} TBStringList;

/* Picture types follow ID3v2 APIC / FLAC (0 = other, 3 = front cover, 4 = back cover, ...). */
typedef struct TBPicture {
    int32_t type;
    const char *mimeType;      /* "image/jpeg", "image/png", ... (may be "" if unknown) */
    const char *description;   /* UTF-8, may be "" */
    const uint8_t *data;
    size_t size;
    /* Optional image geometry, used for FLAC/Vorbis picture blocks (0 = unknown). */
    int32_t width;
    int32_t height;
    int32_t colorDepth;
    int32_t numColors;
} TBPicture;

typedef struct TBPictureList {
    size_t count;
    TBPicture *items;
} TBPictureList;

typedef struct TBFile TBFile;

/* ---------------------------------------------------------------------------------- */
/* Library / lifecycle                                                                  */
/* ---------------------------------------------------------------------------------- */

/* "2.3.2" (static string). */
const char *tb_taglib_version(void);

/* English description of a status code (static string). */
const char *tb_status_message(TBStatus status);

enum {
    TB_OPEN_READ_ONLY = 1u << 0,                /* never open the file for writing */
    TB_OPEN_NO_AUDIO_PROPERTIES = 1u << 1,      /* skip reading audio properties (faster) */
    TB_OPEN_ACCURATE_AUDIO_PROPERTIES = 1u << 2 /* scan more of the file for exact properties */
};

/* Opens a file. On success *outFile receives a handle that must be closed with tb_close().
 * Without TB_OPEN_READ_ONLY the file is opened for reading and writing if possible;
 * if it cannot be opened for writing it is opened read-only (see tb_is_writable()). */
TBStatus tb_open(const char *path, uint32_t flags, TBFile **outFile);

/* Closes the handle (without saving). NULL is ignored. */
void tb_close(TBFile *file);

/* Message of the last failed call on this handle ("" if none). Valid until the next call. */
const char *tb_last_error(const TBFile *file);

/* ---------------------------------------------------------------------------------- */
/* Information                                                                          */
/* ---------------------------------------------------------------------------------- */

TBFileType tb_file_type(const TBFile *file);
/* Human readable format name, e.g. "MP3", "MPEG-4 Audio", "FLAC", "Ogg Vorbis" (static). */
const char *tb_file_format_name(const TBFile *file);
/* Bit mask of TB_TAG_* present on disk when the handle was opened. */
uint32_t tb_tag_types(const TBFile *file);
/* Major version of the ID3v2 tag on disk (2, 3, 4) or 0 if there is none. */
int32_t tb_id3v2_version(const TBFile *file);
/* Tag formats as text, e.g. "ID3v2.4, ID3v1" or "Vorbis Comment" ("" if none). Valid until close. */
const char *tb_tag_format_description(const TBFile *file);
/* 1 if the tags of this file can be written: the format is supported for writing, the file
 * type was verified from its header and TagLib would not lose any metadata on saving
 * (see tb_writable_reason()). This does not depend on how the handle was opened;
 * tb_handle_is_read_only() tells whether this handle can save. */
int32_t tb_is_writable(const TBFile *file);
/* Why the file is not writable ("" if writable). Valid until close. */
const char *tb_writable_reason(const TBFile *file);
/* 1 if the handle was opened read-only (TB_OPEN_READ_ONLY or no write permission). */
int32_t tb_handle_is_read_only(const TBFile *file);
/* 1 if the primary tag format can store embedded pictures. */
int32_t tb_supports_pictures(const TBFile *file);
/* 1 if the primary tag format can store the field. */
int32_t tb_field_supported(const TBFile *file, TBField field);
TBStatus tb_audio_properties(const TBFile *file, TBAudioProperties *out);

/* Checksum of everything that belongs to the audio stream and must never change when tags are
 * written (all tag/metadata areas excluded): MPEG frames; MP4 'mdat' atoms + sample tables
 * (stsd/stts/stsz/stsc); FLAC STREAMINFO/SEEKTABLE/CUESHEET + frames; all Ogg packets except
 * the comment header; WAV 'fmt '+'data'; AIFF 'COMM'+'SSND'; DSF 'fmt '+'data'; DSDIFF
 * 'PROP'+'DSD '; ASF stream properties + data object; APE/WavPack/MPC/TTA everything between
 * leading ID3v2 and trailing APE/ID3v1 tags.
 * Used to verify byte for byte that writing tags did not change the audio stream.
 * Writes "<length>:<crc32>:<adler32>" (NUL-terminated, at most 64 bytes) into out.
 * Returns TB_ERROR_UNSUPPORTED_FORMAT for formats without a known payload layout. */
TBStatus tb_audio_payload_checksum(TBFile *file, char *out, size_t outSize);

/* ---------------------------------------------------------------------------------- */
/* Fields                                                                               */
/* ---------------------------------------------------------------------------------- */

/* Reads a text field. *out is always set on success (count may be 0) and must be freed
 * with tb_string_list_free(). Values are returned as stored (no splitting). */
TBStatus tb_get_strings(TBFile *file, TBField field, TBStringList **out);

/* Writes a text field. count == 0 removes the field. For multi-valued fields every value
 * is one entry; formats without multi-value support store them joined with "; ".
 * Secondary tags present in the file (ID3v1, APE in MP3, RIFF INFO, ...) are updated too. */
TBStatus tb_set_strings(TBFile *file, TBField field, const char *const *values, size_t count);

/* Reads a numeric field. *hasValue is 0 if the field is not present. */
TBStatus tb_get_int(TBFile *file, TBField field, int64_t *value, int32_t *hasValue);

/* Writes a numeric field. hasValue == 0 removes it. */
TBStatus tb_set_int(TBFile *file, TBField field, int64_t value, int32_t hasValue);

/* ---------------------------------------------------------------------------------- */
/* Pictures                                                                             */
/* ---------------------------------------------------------------------------------- */

/* Lists the embedded pictures in file order. Free with tb_picture_list_free(). */
TBStatus tb_get_pictures(TBFile *file, TBPictureList **out);
/* Replaces all pictures by the given list (count == 0 removes all pictures). */
TBStatus tb_set_pictures(TBFile *file, const TBPicture *pictures, size_t count);
/* Appends one picture. */
TBStatus tb_add_picture(TBFile *file, const TBPicture *picture);
/* Removes the picture at index (as returned by tb_get_pictures()). */
TBStatus tb_remove_picture(TBFile *file, size_t index);
/* Replaces the picture at index. */
TBStatus tb_replace_picture(TBFile *file, size_t index, const TBPicture *picture);

/* ---------------------------------------------------------------------------------- */
/* Generic properties (TagLib PropertyMap names, e.g. "MOOD", "MUSICBRAINZ_TRACKID")    */
/* ---------------------------------------------------------------------------------- */

/* All property keys of the file (TagLib unified names). */
TBStatus tb_get_property_keys(TBFile *file, TBStringList **out);
/* Values of one property (count 0 if absent). */
TBStatus tb_get_property(TBFile *file, const char *key, TBStringList **out);
/* Sets one property (count == 0 removes it); all other properties stay untouched. */
TBStatus tb_set_property(TBFile *file, const char *key, const char *const *values, size_t count);
/* Identifiers of data that TagLib cannot express as properties (e.g. "PRIV", "APIC",
 * "UNKNOWN/XYZW", MP4 atom names). Useful to check that such data is preserved. */
TBStatus tb_get_unsupported_properties(TBFile *file, TBStringList **out);

/* ---------------------------------------------------------------------------------- */
/* Saving / memory                                                                      */
/* ---------------------------------------------------------------------------------- */

/* Writes the in-memory tags to the file. Existing tag types are kept (never stripped);
 * an existing ID3v2 tag keeps its version (2.3 stays 2.3, 2.4 stays 2.4, a new tag is 2.4). */
TBStatus tb_save(TBFile *file);

void tb_string_list_free(TBStringList *list);
void tb_picture_list_free(TBPictureList *list);

#ifdef __cplusplus
}
#endif

#endif /* TAGBRIDGE_H */
