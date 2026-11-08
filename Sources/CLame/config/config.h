/*
 * Handgeschriebene config.h für LAME 3.100 (ersetzt die von „configure“ erzeugte Datei).
 *
 * Ziel: macOS 13+ auf arm64 und x86_64, gleiche Einstellungen für beide Architekturen.
 * Kein Assembler (HAVE_NASM fehlt), keine SSE-Intrinsics (HAVE_XMMINTRIN_H fehlt), kein mpglib
 * (HAVE_MPGLIB fehlt, kein Dekodieren). TAKEHIRO_IEEE754_HACK und USE_FAST_LOG sind wie beim
 * configure-Lauf für arm64 NICHT gesetzt – damit rechnen beide Architekturen identisch.
 */
#ifndef LAME_CONFIG_H
#define LAME_CONFIG_H

/* SwiftPM setzt in Debug-Builds -DDEBUG=1 – LAME würde damit Diagnoseausgaben erzeugen. */
#undef DEBUG

#define STDC_HEADERS 1
#define HAVE_ERRNO_H 1
#define HAVE_FCNTL_H 1
#define HAVE_LIMITS_H 1
#define HAVE_INTTYPES_H 1
#define HAVE_STDINT_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRING_H 1
#define HAVE_STRINGS_H 1
#define HAVE_MEMORY_H 1
#define HAVE_UNISTD_H 1
#define HAVE_SYS_STAT_H 1
#define HAVE_SYS_TYPES_H 1
#define HAVE_SYS_TIME_H 1
#define HAVE_STRCHR 1
#define HAVE_MEMCPY 1
#define HAVE_STRTOL 1
#define HAVE_GETTIMEOFDAY 1

/* Ganzzahltypen aus <stdint.h> */
#define HAVE_INT8_T 1
#define HAVE_INT16_T 1
#define HAVE_INT32_T 1
#define HAVE_INT64_T 1
#define HAVE_UINT8_T 1
#define HAVE_UINT16_T 1
#define HAVE_UINT32_T 1
#define HAVE_UINT64_T 1

/* IEEE-754-Gleitkommatypen gibt es unter macOS nicht als eigene Typen */
typedef float ieee754_float32_t;
typedef double ieee754_float64_t;
typedef long double ieee854_float80_t;

#define SIZEOF_SHORT 2
#define SIZEOF_INT 4
#define SIZEOF_LONG 8
#define SIZEOF_LONG_LONG 8
#define SIZEOF_FLOAT 4
#define SIZEOF_DOUBLE 8
#define SIZEOF_UNSIGNED_SHORT 2
#define SIZEOF_UNSIGNED_INT 4
#define SIZEOF_UNSIGNED_LONG 8
#define SIZEOF_UNSIGNED_LONG_LONG 8

#define LAME_LIBRARY_BUILD 1
#define PACKAGE "lame"
#define PACKAGE_NAME "lame"
#define PACKAGE_VERSION "3.100"
#define VERSION "3.100"

#ifndef _DARWIN_USE_64_BIT_INODE
# define _DARWIN_USE_64_BIT_INODE 1
#endif

#endif /* LAME_CONFIG_H */
