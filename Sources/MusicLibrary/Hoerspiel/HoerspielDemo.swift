import Foundation
import MLStudio

/// Feste Inhalte für Vorschaubilder der KI-Hörbücher (erfunden, nur Darstellung – keine Erzeugung).
@MainActor
enum HoerspielDemo {
    static func production() -> HSProduction {
        var p = HSProduction(mode: .hoerspiel, title: "Der Geisterzug von Gleis 7", prompt: HSCreateView.examples[0].1, targetMinutes: 10,
                             created: Date().addingTimeInterval(-7200))
        p.subtitle = "Ein Fall für die Bande vom Wasserturm"
        p.logline = "Im Sommer 1984 hält nachts ein Zug an einem Bahnhof, der seit zehn Jahren stillgelegt ist."
        p.era = "Sommer 1984, Kleinstadt in Niedersachsen"
        p.tone = "spannend, humorvoll"
        p.retroAmount = 0.6
        p.figures = [
            HSFigure(id: "ERZÄHLER", name: "Erzähler", role: "Erzähler", age: 50, gender: "m", description: "ruhig, warm",
                     voice: "warme, ruhige Männerstimme", voiceEN: "A calm, warm male narrator in his fifties"),
            HSFigure(id: "JONAS", name: "Jonas", role: "Hauptfigur", age: 14, gender: "m", description: "Anführer, mutig, etwas vorlaut",
                     voice: "heller Jungenstimme, schnell", voiceEN: "A cheeky 14-year-old boy, bright voice, quick speech"),
            HSFigure(id: "MIRA", name: "Mira", role: "Hauptfigur", age: 14, gender: "w", description: "klug, beobachtet genau",
                     voice: "klare Mädchenstimme", voiceEN: "A clever 14-year-old girl, clear bright voice"),
            HSFigure(id: "BENNO", name: "Benno", role: "Hauptfigur", age: 13, gender: "m", description: "isst gern, ängstlich, witzig",
                     voice: "weiche Jungenstimme", voiceEN: "A soft-spoken 13-year-old boy, slightly nervous"),
            HSFigure(id: "KOWALSKI", name: "Herr Kowalski", role: "Verdächtiger", age: 64, gender: "m", description: "ehemaliger Stellwerker",
                     voice: "raue, tiefe Stimme", voiceEN: "A gruff man in his sixties, low raspy voice"),
        ]
        p.chapters = [HSChapter(number: 1, title: "Licht im Stellwerk")]
        let s1: [HSScriptItem] = [
            HSScriptItem(kind: .music, text: "Titelmusik", english: "main title theme"),
            HSScriptItem(kind: .atmo, text: "Grillen, ferner Wind über dem Bahngelände", english: "crickets at night, light wind over railway yard"),
            HSScriptItem(kind: .line, speaker: "ERZÄHLER", text: "Es war die heißeste Nacht des Sommers, als Jonas, Mira und Benno am alten Bahnhof von Wessel ankamen."),
            HSScriptItem(kind: .line, speaker: "JONAS", emotion: "flüsternd", text: "Da vorne. Seht ihr das Licht im Stellwerk?"),
            HSScriptItem(kind: .line, speaker: "BENNO", emotion: "ängstlich", text: "Ich sehe vor allem, dass es Mitternacht ist und ich Hunger habe."),
            HSScriptItem(kind: .line, speaker: "MIRA", text: "Das Stellwerk ist seit zehn Jahren außer Betrieb. Da dürfte gar kein Strom mehr sein."),
            HSScriptItem(kind: .sfx, text: "Eine schwere Tür quietscht", english: "heavy metal door creaking open"),
            HSScriptItem(kind: .line, speaker: "KOWALSKI", emotion: "streng", text: "Was habt ihr hier zu suchen? Verschwindet nach Hause!"),
        ]
        p.scenes = [
            HSScene(chapter: 1, number: 1, title: "Licht im Stellwerk", location: "Bahnhof Wessel, Bahnsteig", room: "draußen",
                    atmoEN: "crickets at night", outline: "Die drei Freunde sehen nachts Licht im stillgelegten Stellwerk und treffen auf Herrn Kowalski.",
                    participants: ["ERZÄHLER", "JONAS", "MIRA", "BENNO", "KOWALSKI"], summary: "Licht im Stellwerk, Kowalski verjagt die Kinder.",
                    items: s1),
            HSScene(chapter: 1, number: 2, title: "Die Fahrkarte", location: "Miras Zimmer", room: "zimmer", outline: "Mira findet eine Fahrkarte von 1974.",
                    participants: ["MIRA", "JONAS"]),
        ]
        for i in p.scenes[0].items.indices where p.scenes[0].items[i].kind == .line {
            p.scenes[0].items[i].audioFile = "zeilen/demo.wav"
        }
        for f in p.figures {
            p.cast[f.id] = HSCast(referenceFile: "stimmen/\(f.id).wav", referenceText: HSVoiceDesign.referenceText, instruct: f.voiceEN, seed: 1)
        }
        for i in p.scenes[0].items.indices where p.scenes[0].items[i].kind == .line {
            p.scenes[0].items[i].audioFingerprint = p.fingerprint(of: p.scenes[0].items[i])
        }
        p.set(.story, .running)
        p.set(.chapters, .pending)
        p.set(.casting, .done)
        return p
    }

    static func finished() -> HSProduction {
        var p = HSProduction(mode: .hoerbuch, title: "Die Karte des Lehrlings", prompt: HSCreateView.examples[7].1, targetMinutes: 30,
                             created: Date().addingTimeInterval(-86400 * 2))
        p.logline = "Ein Lehrling entdeckt, dass die Orte auf seinen Karten erst entstehen, wenn er sie zeichnet."
        p.figures = [HSFigure(id: "ERZÄHLER", name: "Erzählerin", role: "Erzähler", voiceEN: "A warm female narrator")]
        p.chapters = [HSChapter(number: 1, title: "Tinte"), HSChapter(number: 2, title: "Die weiße Stelle"), HSChapter(number: 3, title: "Heimkehr")]
        // Vorschau: kurze echte Absätze statt Fülltext (Dauer der Demo kommt aus mix.duration)
        let demo: [(String, String, [String])] = [
            ("Die Werkstatt am Hafen", "Lio beginnt seine Lehre bei der Kartenzeichnerin Ilse.",
             ["Die Werkstatt roch nach Leim, Tinte und kaltem Hafenwind.",
              "Meisterin Ilse legte Lio eine leere Seite hin und sagte nur: Zeichne, was du siehst."]),
            ("Die erste Linie", "Lios erste Karte zeigt eine Gasse, die es am Morgen noch nicht gab.",
             ["Am nächsten Morgen stand Lio vor einer Gasse, die es gestern noch nicht gegeben hatte.",
              "Die Pflastersteine waren genau so gesetzt wie auf seinem Blatt."]),
            ("Ilses Schweigen", "Ilse verbietet Lio, weiter ohne Vorlage zu zeichnen.",
             ["Ilse sah lange auf die Karte. Dann schloss sie sie in die oberste Schublade."]),
            ("Aufbruch", "Lio steckt die Karte ein und folgt der neuen Gasse.",
             ["Lio wartete, bis das Licht in Ilses Kammer erlosch, und nahm die Karte an sich."]),
            ("Die weiße Stelle", "Am Ende der Gasse beginnt ein Gebiet, das auf keiner Karte steht.",
             ["Hinter der letzten Laterne hörte die Stadt einfach auf – kein Nebel, keine Mauer, nur Weiß."]),
            ("Der Wächter", "Ein alter Fährmann warnt Lio vor dem, was er zeichnen könnte.",
             ["Der Fährmann tippte auf Lios Feder. Was du zeichnest, bleibt. Auch das, was du fürchtest."]),
            ("Der Fehler", "Ein verwischter Strich lässt eine Brücke halb verschwinden.",
             ["Ein Tropfen fiel aufs Papier, und die Brücke unter Lios Füßen wurde durchsichtig."]),
            ("Ilses Geheimnis", "Ilse findet Lio und erzählt, warum sie keine eigenen Orte mehr zeichnet.",
             ["Ich habe auch einmal eine Stadt gezeichnet, sagte Ilse leise. Sie gibt es heute noch."]),
            ("Heimkehr", "Lio zeichnet den Weg zurück – und lässt eine Seite bewusst frei.",
             ["Lio zog die letzte Linie bis zur Werkstatttür und ließ den Rand der Karte weiß."]),
        ]
        p.scenes = demo.enumerated().map { i, s in
            HSScene(chapter: i / 3 + 1, number: i % 3 + 1, title: s.0, summary: s.1,
                    items: s.2.map { HSScriptItem(kind: .line, speaker: "ERZÄHLER", text: $0) })
        }
        for s in HSStep.allCases where s != .sfx { p.set(s, .done) }
        p.useSFX = false
        p.mix = HSMixInfo(master: "mix/master.wav", stems: [:],
                          chapters: p.chapters.enumerated().map { HSChapterMark(title: "Kapitel \($0.offset + 1): \($0.element.title)", start: Double($0.offset) * 611) },
                          duration: 1834, loudness: -16.0, speechToBackground: 21.4, timeline: "mix/zeitleiste.json")
        p.review = HSReview(problems: [
            HSReviewProblem(scene: 4, problem: "Die Karte liegt am Ende von Szene 3 in Ilses Schublade, in Szene 4 trägt Lio sie ohne Erklärung bei sich",
                            fix: "Lio nimmt die Karte vor dem Aufbruch an sich"),
            HSReviewProblem(scene: 8, problem: "Meisterin Ilse duzt Lio, sonst siezt sie ihn", fix: "einheitlich duzen"),
        ], revised: [4])
        p.scenes[3].replaceItems(p.scenes[3].items, note: "vor dem Lektorat")
        return p
    }

    /// Zeitleiste für die Vorschau des Mehrspur-Editors (Demo ohne Audiodateien).
    static func timeline(_ p: HSProduction) -> HSTimeline {
        var clips: [HSClip] = []
        var t = 24.0
        clips.append(HSClip(id: "m0", track: "Musik", file: "", start: 0, duration: 24, fadeOut: 3, label: "Titelmusik"))
        for (i, s) in p.scenes.enumerated() {
            // Demo-Texte sind gekürzt: Dauer aus der Gesamtlänge verteilen, damit Kapitelmarken passen
            let d = p.mix.map { max(30, ($0.duration - 120) / Double(max(1, p.scenes.count))) } ?? Double(s.spokenWords) / 2.3
            clips.append(HSClip(id: "e\(i)", track: "Erzähler", file: "", start: t, duration: d, label: s.title))
            t += d + 1.2
            if i % 3 == 2 && i < p.scenes.count - 1 {
                clips.append(HSClip(id: "u\(i)", track: "Musik", file: "", start: t, duration: 12, fadeIn: 1, fadeOut: 2, label: "Übergang"))
                t += 12.5
            }
        }
        clips.append(HSClip(id: "m9", track: "Musik", file: "", start: t, duration: 22, fadeIn: 2, fadeOut: 4, label: "Abspann"))
        return HSTimeline(tracks: [HSTrack(name: "Erzähler"), HSTrack(name: "Musik", gainDB: -4)], clips: clips,
                          chapters: p.mix?.chapters ?? [])
    }

    static func voices() -> [HSVoiceProfile] {
        var a = HSVoiceProfile(name: "Kommissar Brandt", kind: .designed,
                               settings: HSVoiceSettings(gender: .male, age: .middle, pitch: -1, timbre: .raspy, tempo: -1, mood: .stern))
        a.referenceFile = "brandt.wav"
        var b = HSVoiceProfile(name: "Kassette 1985 – S2 Hauptfigur", kind: .styleOnly,
                               customDescriptionEN: "A female or teenage voice with high pitch, bright timbre, fast delivery")
        b.sourceReference = "Kassette 1985"
        b.settings.notes = "weiblich oder jugendlich (geschätzt), Tonlage hoch (~248 Hz), hell, schnell, lebendig"
        var c = HSVoiceProfile(name: "Opa Heinz", kind: .authorized)
        c.referenceFile = "heinz.wav"
        var consent = HSConsent(personName: "Heinz Berger", scope: "Familienhörspiele", grantedTo: "Jan", recordingFile: "e.wav")
        consent.similarity = 0.74
        consent.similarityThreshold = 0.5
        consent.transcriptMatches = true
        consent.verified = Date()
        c.consent = consent
        return [a, b, c]
    }

    static func references() -> [HSReference] {
        [HSReference(name: "Kassette 1985", sources: ["Folge 12 – Seite A.mp3"], summary: """
        Dauer 23.4 min, Sprachanteil 81 %, 6 Stimmen erkannt (geschätzt).
        - S1 – Erzähler (geschätzt): 27 % Redeanteil, männlich (geschätzt), Tonlage tief (~98 Hz), dunkel, warm, mittleres Tempo, ruhig, gleichmäßig
        - S2 – Hauptfigur (geschätzt): 22 % Redeanteil, weiblich oder jugendlich (geschätzt), Tonlage hoch (~248 Hz), hell, klar, schnell, lebendig
        Dialog: 14.2 Sprecherwechsel/min, Pause zwischen Repliken ~0.34 s, Repliken ~2.9 s.
        Aufnahme: -19.8 LUFS, Bandbreite bis ~12.4 kHz (begrenzt wie Band/Kassette), Grundrauschen -58.2 dBFS, Nachhall ~0.42 s (geschätzt)
        Ohne Sprache: 96.4 s Musik/Geräusche, 9 Musikbrücken (~6.1 s).
        """, styleHint: "schnelle Wortwechsel, Erzähler mit etwa 27 % Anteil, kurze Musikbrücken zwischen den Szenen",
                     speakers: [], retroSuggested: 1.0)]
    }

    static func sfx() -> [HSSFXEntry] {
        [HSSFXEntry(name: "Tür quietscht", prompt: "heavy metal door creaking open", file: "/Demo/tuer.wav", seconds: 4, origin: "erzeugt",
                    license: "Erzeugt mit Stable Audio 3 small"),
         HSSFXEntry(name: "Grillen bei Nacht", prompt: "crickets at night, light wind", file: "/Demo/grillen.wav", seconds: 20, origin: "erzeugt",
                    license: "Erzeugt mit Stable Audio 3 small"),
         HSSFXEntry(name: "Wählscheibentelefon", prompt: "", file: "/Demo/telefon.wav", seconds: 3, origin: "importiert", license: "eigene Aufnahme")]
    }
}
