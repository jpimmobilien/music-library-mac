package de.privateapp.aether.files

/*
 * Regeln für Datei- und Ordnernamen.
 *
 * Geprüft wird nach den Regeln von FAT/exFAT, weil SD-Karten und USB-Sticks fast immer so formatiert sind und Android
 * diese Regeln für den gesamten gemeinsamen Speicher anwendet. Ein Name, der hier gültig ist, funktioniert damit auf
 * jedem Speicher – es gibt keine Überraschung erst beim Kopieren auf die SD-Karte.
 *
 * Wichtig: Der gemeinsame Speicher von Android unterscheidet NICHT zwischen Groß- und Kleinschreibung („Foto.jpg“ und
 * „foto.JPG“ sind dieselbe Datei). Wer [FileNames.uniqueName] benutzt, muss deshalb in `taken` ohne Rücksicht auf
 * Groß-/Kleinschreibung prüfen.
 */

/** Prüfen und Erzeugen von Namen. */
object FileNames {

    /** Höchstlänge eines Namens in Byte (UTF-8), wie bei ext4, F2FS, FAT (LFN) und exFAT. */
    const val MAX_BYTES = 255

    /** Endung der Zwischendateien, die ORBIT beim sicheren Schreiben verwendet. Nie in Listen sichtbar. */
    const val TEMP_SUFFIX = ".aether-part"

    private const val FORBIDDEN = "\"*:<>?\\|"
    private val COUNTER = Regex("""^(.*\S) ([1-9][0-9]{0,2})$""")
    private val DOUBLE_EXTENSIONS = listOf(".tar.gz", ".tar.bz2", ".tar.xz")

    /** Warum [name] nicht verwendet werden kann – oder `null`, wenn er auf jedem Speicher gültig ist. */
    fun validate(name: String): NameProblem? = when {
        name.isEmpty() -> NameProblem.EMPTY
        name == "." || name == ".." -> NameProblem.DOTS_ONLY
        '/' in name -> NameProblem.SLASH
        name.any { it.code < 0x20 || it.code == 0x7F } -> NameProblem.CONTROL_CHARACTER
        name.any { it in FORBIDDEN } -> NameProblem.FORBIDDEN_CHARACTER
        utf8Length(name) > MAX_BYTES -> NameProblem.TOO_LONG
        name.endsWith('.') || name.endsWith(' ') -> NameProblem.TRAILING_DOT_OR_SPACE
        isReserved(name) -> NameProblem.RESERVED
        else -> null
    }

    /**
     * Ein freier Name nach dem Muster des Finders: „Foto.jpg“ → „Foto 2.jpg“ → „Foto 3.jpg“. Endet der Name schon
     * auf eine kleine Zahl („Foto 2.jpg“), wird sie hochgezählt („Foto 3.jpg“); Jahreszahlen wie „Urlaub 2024“
     * bleiben unangetastet („Urlaub 2024 2“). Ordner und Namen ohne Endung („.nomedia“) werden als Ganzes
     * nummeriert („Ordner 2“, „.nomedia 2“). Das Ergebnis ist nie länger als [MAX_BYTES].
     *
     * [taken] muss Groß-/Kleinschreibung ignorieren (siehe Dateikopf).
     */
    fun uniqueName(desired: String, isDirectory: Boolean, taken: (String) -> Boolean): String {
        if (!taken(desired)) return desired
        val (stem, suffix) = splitForNumbering(desired, isDirectory)
        val counter = COUNTER.matchEntire(stem)
        val base = counter?.groupValues?.get(1) ?: stem
        var n = counter?.groupValues?.get(2)?.toInt()?.plus(1) ?: 2
        while (true) {
            val candidate = compose(base, n, suffix)
            if (!taken(candidate)) return candidate
            n++
        }
    }

    /** Name gehört ORBIT selbst (Zwischendatei oder Papierkorb) und wird nie angezeigt. */
    internal fun isReserved(name: String): Boolean =
        name.endsWith(TEMP_SUFFIX, ignoreCase = true) || name.equals(TrashStore.DIR_NAME, ignoreCase = true)

    private fun splitForNumbering(name: String, isDirectory: Boolean): Pair<String, String> {
        if (isDirectory) return name to ""
        for (double in DOUBLE_EXTENSIONS) {
            if (name.length > double.length && name.endsWith(double, ignoreCase = true)) {
                val cut = name.length - double.length
                return name.substring(0, cut) to name.substring(cut)
            }
        }
        val extension = FileTypes.extensionOf(name)
        if (extension.isEmpty()) return name to ""
        val cut = name.length - extension.length - 1
        return name.substring(0, cut) to name.substring(cut)
    }

    private fun compose(base: String, n: Int, suffix: String): String {
        val tail = " $n$suffix"
        val room = MAX_BYTES - utf8Length(tail)
        if (room <= 0) return fitToBytes(tail.trimStart(), MAX_BYTES)
        return fitToBytes(base, room).trimEnd() + tail
    }

    /** Länge von [s] in UTF-8 – wie `toByteArray(UTF_8)`, aber ohne die Bytes zu erzeugen. */
    internal fun utf8Length(s: String): Int {
        var bytes = 0
        var i = 0
        while (i < s.length) {
            val (length, width) = codePointUtf8(s, i)
            bytes += length
            i += width
        }
        return bytes
    }

    /** Kürzt [s] am Ende (nie mitten in einem Zeichen), bis es höchstens [maxBytes] UTF-8-Byte lang ist. */
    internal fun fitToBytes(s: String, maxBytes: Int): String {
        var bytes = 0
        var i = 0
        while (i < s.length) {
            val (length, width) = codePointUtf8(s, i)
            if (bytes + length > maxBytes) break
            bytes += length
            i += width
        }
        return s.substring(0, i)
    }

    /** (UTF-8-Länge, Anzahl Char) des Zeichens an [index]; ein einzelnes Surrogat wird wie „?“ gezählt. */
    private fun codePointUtf8(s: String, index: Int): Pair<Int, Int> {
        val c = s[index]
        return when {
            c.code < 0x80 -> 1 to 1
            c.code < 0x800 -> 2 to 1
            c.isHighSurrogate() && index + 1 < s.length && s[index + 1].isLowSurrogate() -> 4 to 2
            c.isSurrogate() -> 1 to 1
            else -> 3 to 1
        }
    }
}
