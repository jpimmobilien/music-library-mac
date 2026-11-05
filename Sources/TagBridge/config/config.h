/* config.h – hand-written equivalent of TagLib's CMake-generated config.h
 * (from config.h.cmake of TagLib 2.3.2) for the SwiftPM build.
 * Valid for clang/gcc on macOS (arm64, x86_64) and Linux. */

#ifndef TAGLIB_CONFIG_H
#define TAGLIB_CONFIG_H

/* Defined if your compiler supports some byte swap functions */
#define HAVE_GCC_BYTESWAP 1
/* #undef HAVE_GLIBC_BYTESWAP */
/* #undef HAVE_MSC_BYTESWAP */
/* #undef HAVE_MAC_BYTESWAP */
/* #undef HAVE_OPENBSD_BYTESWAP */

/* Defined if your compiler supports ISO _strdup */
/* #undef HAVE_ISO_STRDUP */

/* Defined if zlib is installed (linked via linkerSettings: .linkedLibrary("z")) */
#define HAVE_ZLIB 1

/* Indicates whether debug messages are shown even in release mode */
/* #undef TRACE_IN_RELEASE */

/* TESTS_DIR / TESTS_TMPDIR are only used by TagLib's own unit tests (not vendored). */

#endif
