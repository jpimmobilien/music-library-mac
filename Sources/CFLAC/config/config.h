/*
 * Handgeschriebene config.h für libFLAC 1.5.0 (ersetzt die von CMake/configure erzeugte Datei).
 *
 * Ziel: macOS 13+ auf arm64 und x86_64 mit identischem, einfachem C-Code:
 * kein Ogg (FLAC__HAS_OGG 0), kein Assembler (FLAC__NO_ASM), keine Intrinsics (SSE/AVX/NEON aus),
 * keine Threads (HAVE_PTHREAD fehlt – der Encoder arbeitet einfädig).
 */
#ifndef CFLAC_CONFIG_H
#define CFLAC_CONFIG_H

/* SwiftPM setzt in Debug-Builds -DDEBUG=1; libFLAC soll sich in Debug und Release gleich verhalten. */
#undef DEBUG

#define CPU_IS_BIG_ENDIAN 0
#define CPU_IS_LITTLE_ENDIAN 1
#define WORDS_BIGENDIAN 0
#define ENABLE_64_BIT_WORDS 1

#define FLAC__HAS_OGG 0
#define OGG_FOUND 0

/* Kein Assembler und keine Intrinsics – für arm64 und x86_64 derselbe portable C-Code */
#define FLAC__NO_ASM 1
#define FLAC__HAS_X86INTRIN 0
#define FLAC__HAS_NEONINTRIN 0
#define FLAC__HAS_A64NEONINTRIN 0

#define FLAC__SYS_DARWIN 1

#define HAVE_BSWAP16 1
#define HAVE_BSWAP32 1
#define HAVE_FSEEKO 1
#define HAVE_INTTYPES_H 1
#define HAVE_LROUND 1
#define HAVE_MEMORY_H 1
#define HAVE_STDINT_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRING_H 1
#define HAVE_SYS_PARAM_H 1
#define HAVE_SYS_STAT_H 1
#define HAVE_SYS_TIME_H 1
#define HAVE_SYS_TYPES_H 1
#define HAVE_UNISTD_H 1
#define HAVE_TYPEOF 1

#define PACKAGE_VERSION "1.5.0"

#ifndef _DARWIN_USE_64_BIT_INODE
# define _DARWIN_USE_64_BIT_INODE 1
#endif
#ifndef _FILE_OFFSET_BITS
# define _FILE_OFFSET_BITS 64
#endif

#endif /* CFLAC_CONFIG_H */
