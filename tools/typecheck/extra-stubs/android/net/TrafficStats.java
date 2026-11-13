package android.net;

/**
 * Nur für die Typprüfung ohne Android-SDK: TrafficStats gehört seit Android 12 zum Connectivity-Modul, dessen
 * API-Datei nicht in den Framework-Stubs der Werkzeugkette enthalten ist. Der echte Build (Gradle, android.jar)
 * verwendet die Klasse des SDK; dieser Platzhalter wird nie ausgeliefert.
 */
public class TrafficStats {
    public static final int UNSUPPORTED = -1;

    public static long getTotalRxBytes() { throw new RuntimeException("Stub"); }

    public static long getTotalTxBytes() { throw new RuntimeException("Stub"); }
}
