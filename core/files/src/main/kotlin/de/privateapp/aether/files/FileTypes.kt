package de.privateapp.aether.files

import java.util.Locale

/*
 * Dateiarten und MIME-Typen – rein nach Name und Endung, ohne die Datei zu öffnen.
 *
 * Die Tabelle deckt ab, was auf Android-Telefonen tatsächlich vorkommt (Kamera, Messenger, Downloads, Büro).
 * Ein MIME-Typ, den das System liefert (z. B. aus dem MediaStore), hat Vorrang vor der Endung; passt er zu keiner
 * Art, entscheidet die Endung. Unbekanntes ist ehrlich „Datei“ ([FileKind.OTHER]) mit MIME-Typ `null`.
 */

/** Ordnet Dateinamen eine [FileKind] und einen MIME-Typ zu. */
object FileTypes {

    private class TypeInfo(val mimeType: String?, val kind: FileKind)

    private val byExtension: Map<String, TypeInfo> = buildMap {
        fun add(kind: FileKind, mime: String?, vararg extensions: String) {
            for (extension in extensions) put(extension, TypeInfo(mime, kind))
        }
        add(FileKind.IMAGE, "image/jpeg", "jpg", "jpeg")
        add(FileKind.IMAGE, "image/png", "png")
        add(FileKind.IMAGE, "image/gif", "gif")
        add(FileKind.IMAGE, "image/webp", "webp")
        add(FileKind.IMAGE, "image/heic", "heic")
        add(FileKind.IMAGE, "image/heif", "heif")
        add(FileKind.IMAGE, "image/avif", "avif")
        add(FileKind.IMAGE, "image/bmp", "bmp")
        add(FileKind.IMAGE, "image/svg+xml", "svg")

        add(FileKind.VIDEO, "video/mp4", "mp4")
        add(FileKind.VIDEO, "video/x-matroska", "mkv")
        add(FileKind.VIDEO, "video/webm", "webm")
        add(FileKind.VIDEO, "video/3gpp", "3gp")
        add(FileKind.VIDEO, "video/quicktime", "mov")
        add(FileKind.VIDEO, "video/x-msvideo", "avi")

        add(FileKind.AUDIO, "audio/mpeg", "mp3")
        add(FileKind.AUDIO, "audio/mp4", "m4a")
        add(FileKind.AUDIO, "audio/aac", "aac")
        add(FileKind.AUDIO, "audio/ogg", "ogg")
        add(FileKind.AUDIO, "audio/opus", "opus")
        add(FileKind.AUDIO, "audio/flac", "flac")
        add(FileKind.AUDIO, "audio/x-wav", "wav")
        add(FileKind.AUDIO, "audio/amr", "amr")

        add(FileKind.PDF, "application/pdf", "pdf")

        add(FileKind.TEXT, "text/plain", "txt", "log", "ini")
        add(FileKind.TEXT, "text/markdown", "md")
        add(FileKind.TEXT, "text/csv", "csv")
        add(FileKind.TEXT, "application/json", "json")
        add(FileKind.TEXT, "text/xml", "xml")
        add(FileKind.TEXT, "application/yaml", "yaml", "yml")
        add(FileKind.TEXT, "text/x-kotlin", "kt")
        add(FileKind.TEXT, "text/x-java", "java")
        add(FileKind.TEXT, "text/html", "html", "htm")
        add(FileKind.TEXT, "text/css", "css")
        add(FileKind.TEXT, "text/javascript", "js")
        add(FileKind.TEXT, "text/x-vcard", "vcf")
        add(FileKind.TEXT, "text/calendar", "ics")

        add(FileKind.DOCUMENT, "application/msword", "doc")
        add(FileKind.DOCUMENT, "application/vnd.openxmlformats-officedocument.wordprocessingml.document", "docx")
        add(FileKind.DOCUMENT, "application/vnd.oasis.opendocument.text", "odt")
        add(FileKind.DOCUMENT, "application/rtf", "rtf")
        add(FileKind.DOCUMENT, "application/vnd.ms-excel", "xls")
        add(FileKind.DOCUMENT, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "xlsx")
        add(FileKind.DOCUMENT, "application/vnd.oasis.opendocument.spreadsheet", "ods")
        add(FileKind.DOCUMENT, "application/vnd.ms-powerpoint", "ppt")
        add(FileKind.DOCUMENT, "application/vnd.openxmlformats-officedocument.presentationml.presentation", "pptx")
        add(FileKind.DOCUMENT, "application/vnd.oasis.opendocument.presentation", "odp")
        add(FileKind.DOCUMENT, "application/epub+zip", "epub")

        add(FileKind.ARCHIVE, "application/zip", "zip")
        add(FileKind.ARCHIVE, "application/vnd.rar", "rar")
        add(FileKind.ARCHIVE, "application/x-7z-compressed", "7z")
        add(FileKind.ARCHIVE, "application/x-tar", "tar")
        add(FileKind.ARCHIVE, "application/gzip", "gz", "tgz")
        add(FileKind.ARCHIVE, "application/x-bzip2", "bz2")
        add(FileKind.ARCHIVE, "application/x-xz", "xz")

        add(FileKind.APK, "application/vnd.android.package-archive", "apk")
        // Für App-Bündel gibt es keinen registrierten MIME-Typ – deshalb ehrlich `null`.
        add(FileKind.APK, null, "apks", "xapk", "aab")
    }

    /** MIME-Typ → Art, für Typen, die nicht schon am Präfix („image/“ …) erkennbar sind. */
    private val kindByMime: Map<String, FileKind> = buildMap {
        for (info in byExtension.values) {
            val mime = info.mimeType ?: continue
            if (!containsKey(mime)) put(mime, info.kind)
        }
        put("application/ogg", FileKind.AUDIO)
        put("application/x-zip-compressed", FileKind.ARCHIVE)
        put("application/x-rar-compressed", FileKind.ARCHIVE)
        put("application/x-gzip", FileKind.ARCHIVE)
        put("application/javascript", FileKind.TEXT)
        put("application/xml", FileKind.TEXT)
        put("application/x-yaml", FileKind.TEXT)
    }

    /**
     * Endung in Kleinbuchstaben ohne Punkt, „“ wenn keine. Ein führender Punkt macht noch keine Endung
     * („.nomedia“ → „“); bei mehreren Punkten zählt der letzte („a.tar.gz“ → „gz“).
     */
    fun extensionOf(name: String): String {
        val dot = name.lastIndexOf('.')
        if (dot <= 0 || dot == name.length - 1) return ""
        return name.substring(dot + 1).lowercase(Locale.ROOT)
    }

    /** MIME-Typ zu einer Endung (mit oder ohne Punkt, Groß-/Kleinschreibung egal) oder `null`, wenn unbekannt. */
    fun mimeTypeOf(extension: String): String? =
        byExtension[extension.removePrefix(".").lowercase(Locale.ROOT)]?.mimeType

    /**
     * Alle bekannten Endungen einer Art (Kleinbuchstaben, ohne Punkt) – z. B. für Kategoriefilter im Medienindex.
     * Für [FileKind.FOLDER] und [FileKind.OTHER] leer.
     */
    fun extensionsOf(kind: FileKind): Set<String> = extensionsByKind[kind].orEmpty()

    private val extensionsByKind: Map<FileKind, Set<String>> by lazy {
        byExtension.entries.groupBy({ it.value.kind }, { it.key }).mapValues { (_, list) -> list.toSortedSet() }
    }

    /** Art einer Datei: Ordner zuerst, dann ein bekannter MIME-Typ, dann die Endung. */
    fun kindOf(name: String, isDirectory: Boolean, mimeType: String? = null): FileKind {
        if (isDirectory) return FileKind.FOLDER
        if (mimeType != null) kindOfMime(mimeType)?.let { return it }
        return byExtension[extensionOf(name)]?.kind ?: FileKind.OTHER
    }

    private fun kindOfMime(mimeType: String): FileKind? {
        val mime = mimeType.substringBefore(';').trim().lowercase(Locale.ROOT)
        return when {
            mime.isEmpty() -> null
            mime == "application/pdf" -> FileKind.PDF
            mime == "application/vnd.android.package-archive" -> FileKind.APK
            mime.startsWith("image/") -> FileKind.IMAGE
            mime.startsWith("video/") -> FileKind.VIDEO
            mime.startsWith("audio/") -> FileKind.AUDIO
            mime.startsWith("text/") -> FileKind.TEXT
            else -> kindByMime[mime]
        }
    }
}
