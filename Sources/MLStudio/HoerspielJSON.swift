import Foundation

// Übersetzung zwischen dem Datenmodell der App und dem JSON-Format des Hörspiel-Prozesses (hs_story/hs_produce).
// Reine Logik, unter Linux getestet.

public enum HSJSON {
    // MARK: Konzept → Produktion

    /// Konzept des Sprachmodells übernehmen: Titel, Figuren, Kapitel und Szenenplan (noch ohne Drehbuch).
    public static func apply(concept c: [String: Any], to p: inout HSProduction) {
        p.title = str(c["titel"]).isEmpty ? p.title : str(c["titel"])
        p.subtitle = str(c["untertitel"])
        p.logline = str(c["logline"])
        p.era = str(c["epoche_ort"])
        p.tone = str(c["ton"])
        p.resolution = str(c["aufloesung"])
        p.clues = (c["spuren"] as? [[String: Any]] ?? []).compactMap { d in
            let text = str(d["spur"])
            guard !text.isEmpty, let n = int(d["szene"]) else { return nil }
            return HSClue(clue: text, scene: n, meaning: str(d["bedeutung"]))
        }
        p.review = nil
        p.figures = (c["figuren"] as? [[String: Any]] ?? []).map(figure)
        p.chapters = []
        p.scenes = []
        for k in c["kapitel"] as? [[String: Any]] ?? [] {
            let nr = int(k["nr"]) ?? (p.chapters.count + 1)
            p.chapters.append(HSChapter(number: nr, title: str(k["titel"])))
            for s in k["szenen"] as? [[String: Any]] ?? [] {
                p.scenes.append(HSScene(chapter: nr, number: int(s["nr"]) ?? (p.scenes.count + 1), title: str(s["titel"]),
                                        location: str(s["ort"]), room: str(s["raum"]).isEmpty ? "zimmer" : str(s["raum"]).lowercased(),
                                        atmoEN: str(s["atmo_en"]), outline: str(s["inhalt"]),
                                        participants: (s["figuren"] as? [Any] ?? []).map { HSFigure.normalizedID(str($0)) }))
            }
        }
    }

    public static func figure(_ f: [String: Any]) -> HSFigure {
        HSFigure(id: str(f["id"]).isEmpty ? str(f["name"]) : str(f["id"]), name: str(f["name"]), role: str(f["rolle"]),
                 age: int(f["alter"]), gender: f["geschlecht"] as? String, description: str(f["beschreibung"]),
                 voice: str(f["stimme"]), voiceEN: str(f["voice_en"]), addedByModel: (f["ergaenzt"] as? Bool) ?? false)
    }

    /// Konzept im Format des Prozesses (für das Schreiben einzelner Szenen).
    public static func concept(_ p: HSProduction) -> [String: Any] {
        var chapters: [[String: Any]] = []
        for ch in p.chapters {
            let scenes = p.scenes.filter { $0.chapter == ch.number }.map { s -> [String: Any] in
                ["nr": s.number, "titel": s.title, "ort": s.location, "raum": s.room, "atmo_en": s.atmoEN, "inhalt": s.outline,
                 "figuren": !s.participants.isEmpty ? s.participants : (s.speakers.isEmpty ? p.figures.map(\.id) : s.speakers)]
            }
            chapters.append(["nr": ch.number, "titel": ch.title, "szenen": scenes])
        }
        return ["titel": p.title, "untertitel": p.subtitle, "logline": p.logline, "epoche_ort": p.era, "ton": p.tone,
                "aufloesung": p.resolution, "figuren": p.figures.map(figureJSON), "kapitel": chapters,
                "spuren": (p.clues ?? []).map { ["spur": $0.clue, "szene": $0.scene, "bedeutung": $0.meaning] },
                "_mode": p.mode.rawValue, "_style": p.narration, "_minutes": p.targetMinutes, "_language": p.language]
    }

    public static func figureJSON(_ f: HSFigure) -> [String: Any] {
        var d: [String: Any] = ["id": f.id, "name": f.name, "rolle": f.role, "beschreibung": f.description, "stimme": f.voice,
                                "voice_en": f.voiceEN, "ergaenzt": f.addedByModel]
        if let a = f.age { d["alter"] = a }
        if let g = f.gender { d["geschlecht"] = g }
        return d
    }

    /// Funde des Lektorats aus der Antwort des Prozesses (ungültige Szenennummern werden verworfen).
    public static func problems(_ list: [[String: Any]], sceneCount: Int) -> [HSReviewProblem] {
        list.compactMap { d in
            guard let n = int(d["szene"]), (1...max(1, sceneCount)).contains(n), !str(d["problem"]).isEmpty else { return nil }
            return HSReviewProblem(scene: n, problem: str(d["problem"]), fix: str(d["korrektur"]))
        }
    }

    public static func problemJSON(_ p: HSReviewProblem) -> [String: Any] {
        ["szene": p.scene, "problem": p.problem, "korrektur": p.fix]
    }

    // MARK: Szene

    public static func items(_ list: [[String: Any]]) -> [HSScriptItem] {
        list.compactMap { i in
            switch str(i["type"]) {
            case "line":
                return HSScriptItem(kind: .line, speaker: HSFigure.normalizedID(str(i["speaker"])), emotion: nonEmpty(i["emotion"]),
                                    text: str(i["text"]))
            case "sfx": return HSScriptItem(kind: .sfx, text: str(i["de"]), english: nonEmpty(i["en"]))
            case "atmo": return HSScriptItem(kind: .atmo, text: str(i["de"]), english: nonEmpty(i["en"]))
            case "music": return HSScriptItem(kind: .music, text: str(i["de"]), english: nonEmpty(i["en"]))
            case "pause": return HSScriptItem(kind: .pause, text: "", seconds: double(i["seconds"]) ?? 1.5)
            default: return nil
            }
        }
    }

    public static func itemJSON(_ i: HSScriptItem) -> [String: Any] {
        switch i.kind {
        case .line: return ["type": "line", "speaker": i.speaker ?? HSFigure.narratorID, "emotion": i.emotion ?? "", "text": i.text]
        case .pause: return ["type": "pause", "seconds": i.seconds ?? 1.5, "de": "", "en": ""]
        default: return ["type": i.kind.rawValue, "de": i.text, "en": i.english ?? i.text]
        }
    }

    /// Ergebnis einer geschriebenen Szene übernehmen; neue Nebenfiguren werden ergänzt.
    public static func apply(scene s: [String: Any], at index: Int, to p: inout HSProduction, note: String = "neu geschrieben") {
        guard p.scenes.indices.contains(index) else { return }
        let newItems = items(s["items"] as? [[String: Any]] ?? [])
        if p.scenes[index].items.isEmpty {
            p.scenes[index].items = newItems
        } else {
            p.scenes[index].replaceItems(newItems, note: note)
        }
        p.scenes[index].summary = str(s["summary"])
        for sp in Set(newItems.compactMap(\.speaker)) where p.figure(sp) == nil {
            p.figures.append(HSFigure(id: sp, name: sp.capitalized, role: "Nebenfigur",
                                      description: "vom Sprachmodell während des Schreibens ergänzt",
                                      voiceEN: "An adult German voice, natural mid-range, clear diction", addedByModel: true))
        }
        p.markChanged(scene: p.scenes[index].id)
    }

    /// Ganze Produktion im Format von hs_produce.assemble.
    public static func story(_ p: HSProduction) -> [String: Any] {
        ["concept": concept(p),
         "scenes": p.scenes.map { s -> [String: Any] in
             ["title": s.title, "room": s.room, "atmo_en": s.atmoEN, "chapter": s.chapter, "scene": s.number,
              "items": s.items.map(itemJSON), "text": ""]
         }]
    }

    /// Schlüssel einer Zeile wie in hs_produce.line_list (Szene ab 1, Element ab 0).
    public static func lineKey(scene: Int, item: Int) -> String {
        "s" + pad(scene + 1, 2) + "_" + pad(item, 3)
    }

    // MARK: Hilfen

    static func pad(_ n: Int, _ width: Int) -> String {
        let s = String(n)
        return String(repeating: "0", count: max(0, width - s.count)) + s
    }

    public static func str(_ v: Any?) -> String {
        if let s = v as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let n = v as? NSNumber { return n.stringValue }
        return ""
    }

    public static func nonEmpty(_ v: Any?) -> String? {
        let s = str(v)
        return s.isEmpty ? nil : s
    }

    public static func int(_ v: Any?) -> Int? {
        if let n = v as? Int { return n }
        if let n = v as? NSNumber { return n.intValue }
        if let s = v as? String { return Int(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    public static func double(_ v: Any?) -> Double? {
        if let n = v as? Double { return n }
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String { return Double(s) }
        return nil
    }
}
