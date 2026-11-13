import Foundation
import MLStudio

/// Feste Inhalte für Vorschaubilder der KI-Musik (erfunden, nur Darstellung – keine Erzeugung).
@MainActor
enum KIMusicDemo {
    static func creations() -> [KICreation] {
        let now = Date()
        func c(_ title: String, _ kind: KICreation.Kind, _ prompt: String, hours: Double, duration: Double, lang: String? = nil,
               seed: Int, favorite: Bool = false, exported: Bool = false) -> KICreation {
            KICreation(title: title, kind: kind, date: now.addingTimeInterval(-hours * 3600), file: "\(title).flac", duration: duration,
                       prompt: prompt, language: lang, seed: seed, model: "acestep-v15-turbo", modelVersion: "ACE-Step 1.5",
                       favorite: favorite, exportedPath: exported ? "/Demo/Musik/KI-Musik/\(title).m4a" : nil)
        }
        return [
            c("Melancholischer Synthwave im Stil", .instrumental, "Melancholischer Synthwave im Stil der 1980er-Jahre: warme analoge Synthesizer, tiefer Bass, keine Vocals.",
              hours: 0.2, duration: 180, seed: 418_223, favorite: true),
            c("Sommerabend am See", .song, "Ein fröhlicher deutscher Popsong über einen Sommerabend am See, Frauenstimme, Gitarre.",
              hours: 3, duration: 150, lang: "de", seed: 42, exported: true),
            c("Lo-Fi zum Lernen", .instrumental, "Entspannter Lo-Fi-Hip-Hop mit warmen Klavierakkorden und leisem Vinylknistern.",
              hours: 27, duration: 120, seed: 1234),
            c("Nachtzug nach Lissabon (Jazz-Version)", .remix, "Jazz-Trio-Version mit Kontrabass, Besen am Schlagzeug und Klavier.",
              hours: 50, duration: 200, seed: 5),
        ]
    }

    static let request = KIGenerationRequest(
        prompt: "Erstelle einen emotionalen deutschen Popsong über eine verlorene Liebe. Eine warme männliche Stimme, ausdrucksstarker Gesang, Klavier, Streicher und ein großer emotionaler Refrain. Moderne, hochwertige Popproduktion.",
        lyricsMode: .aiWrites, language: "de", duration: 180, variations: 2, quality: .balanced)

    static let lyrics = """
    [Verse 1]
    Dein Mantel hängt noch an der Tür
    der Kaffee wird schon kalt
    ich zähl die Schritte bis zu dir
    doch keiner kommt zurück

    [Chorus]
    Und alles, was bleibt, ist ein leises Licht
    ein Lied, das nach dir fragt
    """
}
