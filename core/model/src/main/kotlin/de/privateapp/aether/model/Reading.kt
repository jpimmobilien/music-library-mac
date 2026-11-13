package de.privateapp.aether.model

/*
 * Grundsatz von ORBIT: Jeder angezeigte Wert sagt, woher er kommt – oder warum es ihn nicht gibt.
 * Es werden keine Ersatzwerte erfunden. Ein fehlender Wert ist ein normaler, beschriebener Zustand.
 */

/** Wie ein Wert zustande kam. */
enum class ValueKind(val label: String) {
    /** Direkt von Android gemeldet (z. B. Akkustand, Thermalstatus). */
    REPORTED("von Android gemeldet"),

    /** Aus mehreren gemeldeten Werten berechnet (z. B. belegt = gesamt − frei). */
    DERIVED("berechnet"),

    /** Näherung, die nicht exakt sein muss (wird immer ausdrücklich so gekennzeichnet). */
    ESTIMATED("geschätzt"),
}

/** Grund, warum ein Wert fehlt. */
sealed interface Missing {
    /** Kurzer, verständlicher Text für die Oberfläche. */
    val text: String

    /** Das Gerät bzw. Android stellt diesen Wert nicht bereit. */
    data object NotReported : Missing {
        override val text = "Nicht verfügbar auf diesem Gerät"
    }

    /** Die nötige Schnittstelle gibt es erst ab einer neueren Android-Version. */
    data class RequiresAndroid(val apiLevel: Int, val release: String) : Missing {
        override val text get() = "Erst ab Android $release verfügbar"
    }

    /** Android hat einen Wert geliefert, der physikalisch nicht plausibel ist – er wird nicht angezeigt. */
    data class Implausible(val raw: String) : Missing {
        override val text get() = "Gerät meldet keinen plausiblen Wert ($raw)"
    }

    /** Der Datenträger ist nicht eingebunden (z. B. SD-Karte entnommen oder wird geprüft). */
    data object NotMounted : Missing {
        override val text = "Datenträger nicht eingebunden"
    }

    /** Die Abfrage ist fehlgeschlagen (Android hat sie abgelehnt oder einen Fehler gemeldet). */
    data class Failed(val detail: String?) : Missing {
        override val text get() = if (detail.isNullOrBlank()) "Abfrage fehlgeschlagen" else "Abfrage fehlgeschlagen: $detail"
    }

    /** Der Wert wurde noch nicht gelesen (erster Abruf läuft). */
    data object Pending : Missing {
        override val text = "Wird gelesen …"
    }

    /**
     * Der Wert ist im Moment nicht bestimmbar – [text] nennt die Bedingung (z. B. „Erst in Bewegung bestimmbar“,
     * „Kein aktuelles GPS-Signal“). Für Live-Messungen, bei denen der Grund vom Augenblick abhängt, nicht vom Gerät.
     */
    data class Condition(override val text: String) : Missing
}

/** Ein Messwert oder der beschriebene Grund für sein Fehlen. */
sealed interface Reading<out T> {
    data class Value<out T>(
        val value: T,
        val kind: ValueKind = ValueKind.REPORTED,
        /** Datenquelle in Klartext, z. B. „Akku-Sensor (BatteryManager)“. */
        val source: String,
    ) : Reading<T>

    data class Unavailable(val missing: Missing) : Reading<Nothing>
}

/** Der Wert, falls vorhanden. */
val <T> Reading<T>.valueOrNull: T?
    get() = (this as? Reading.Value<T>)?.value

fun <T, R> Reading<T>.map(transform: (T) -> R): Reading<R> = when (this) {
    is Reading.Value -> Reading.Value(transform(value), kind, source)
    is Reading.Unavailable -> this
}

fun <T> reported(value: T, source: String): Reading<T> = Reading.Value(value, ValueKind.REPORTED, source)

fun <T> derived(value: T, source: String): Reading<T> = Reading.Value(value, ValueKind.DERIVED, source)

fun unavailable(missing: Missing): Reading<Nothing> = Reading.Unavailable(missing)
