package de.privateapp.aether.files

import java.text.Collator
import java.util.Locale

/*
 * Sortierung wie im Finder: „natürlich“ statt nach Zeichencodes.
 *
 *  - Zahlen werden als Zahlen verglichen: „Foto 2“ vor „Foto 10“.
 *  - Groß-/Kleinschreibung zählt nicht: „banane“ vor „Birne“.
 *  - Deutsche Regeln: „Äpfel“ steht bei „Apfel“, nicht hinter „Z“ – auch wenn der Umlaut zerlegt gespeichert ist
 *    („A“ + Trema, wie ihn macOS auf SD-Karten schreibt).
 *  - Bei völliger Gleichheit entscheidet der unveränderte Text, damit die Reihenfolge immer gleich bleibt.
 */

/** Natürliche Sortierung von Namen und Dateilisten. */
object FileSorting {

    /** Ein Collator ist nicht threadsicher – deshalb einer je Thread. */
    private val collator: ThreadLocal<Collator> = ThreadLocal.withInitial {
        Collator.getInstance(Locale.GERMANY).apply {
            strength = Collator.SECONDARY
            decomposition = Collator.CANONICAL_DECOMPOSITION
        }
    }

    /** Vergleicht Namen natürlich (Zahlen als Zahlen, ohne Groß-/Kleinschreibung, deutsche Umlautregeln). */
    val naturalNameComparator: Comparator<String> = Comparator { a, b -> compareNatural(a, b) }

    /**
     * Sortiert [entries] nach [order]. Gleichstände entscheidet der Name (aufsteigend). [SortKey.KIND] sortiert nach
     * der Bezeichnung der Art, [SortKey.SIZE] sortiert Ordner untereinander nach Namen (ihre Größe ist hier 0).
     * Mit [foldersFirst] stehen Ordner immer oben – unabhängig von der Richtung.
     */
    fun sorted(entries: List<FileEntry>, order: SortOrder, foldersFirst: Boolean = true): List<FileEntry> {
        val byName = Comparator<FileEntry> { a, b -> compareNatural(a.name, b.name) }
        val primary: Comparator<FileEntry> = when (order.key) {
            SortKey.NAME -> byName
            SortKey.DATE -> compareBy<FileEntry> { it.modifiedMillis }
            SortKey.SIZE -> Comparator { a, b ->
                if (a.isDirectory && b.isDirectory) 0 else a.sizeBytes.compareTo(b.sizeBytes)
            }
            SortKey.KIND -> Comparator { a, b -> collator.get().compare(a.kind.label, b.kind.label) }
        }
        val directed = if (order.ascending) primary else primary.reversed()
        val complete = directed.then(byName).then(compareBy<FileEntry> { it.path })
        val withFolders = if (foldersFirst) compareBy<FileEntry> { !it.isDirectory }.then(complete) else complete
        return entries.sortedWith(withFolders)
    }

    private fun compareNatural(a: String, b: String): Int {
        val coll = collator.get()
        var i = 0
        var j = 0
        while (i < a.length && j < b.length) {
            val digitA = isAsciiDigit(a[i])
            val digitB = isAsciiDigit(b[j])
            if (digitA && digitB) {
                val endA = runEnd(a, i, digits = true)
                val endB = runEnd(b, j, digits = true)
                val numberA = a.substring(i, endA).trimStart('0')
                val numberB = b.substring(j, endB).trimStart('0')
                if (numberA.length != numberB.length) return numberA.length.compareTo(numberB.length)
                val byValue = numberA.compareTo(numberB)
                if (byValue != 0) return if (byValue < 0) -1 else 1
                i = endA
                j = endB
            } else {
                // Ziffernfolgen sind leer, wenn nur eine Seite eine Zahl hat – dann stehen Zahlen vor Buchstaben.
                val endA = runEnd(a, i, digits = false)
                val endB = runEnd(b, j, digits = false)
                val byText = coll.compare(a.substring(i, endA), b.substring(j, endB))
                if (byText != 0) return byText
                i = endA
                j = endB
            }
        }
        val restA = a.length - i
        val restB = b.length - j
        if (restA != restB) return restA.compareTo(restB)
        return a.compareTo(b)
    }

    private fun isAsciiDigit(c: Char): Boolean = c in '0'..'9'

    private fun runEnd(s: String, start: Int, digits: Boolean): Int {
        var k = start
        while (k < s.length && isAsciiDigit(s[k]) == digits) k++
        return k
    }
}
