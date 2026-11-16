import Foundation

// Mehrspur-Zeitleiste einer Produktion (reine Logik, unter Linux getestet). Format wie hs_audio.Timeline.save:
// Clips verweisen auf Quelldateien (mit Raumklang/Panorama); Blenden, Pegel, Verschieben und Schneiden sind
// verlustfrei – erst „Abmischen“ rechnet sie ein.

public struct HSTrack: Codable, Hashable, Sendable {
    public var name: String
    public var gainDB: Double
    public var mute: Bool
    public var solo: Bool

    enum CodingKeys: String, CodingKey { case name, gainDB = "gain_db", mute, solo }

    public init(name: String, gainDB: Double = 0, mute: Bool = false, solo: Bool = false) {
        self.name = name
        self.gainDB = gainDB
        self.mute = mute
        self.solo = solo
    }

    public var isVoice: Bool { name == "Erzähler" || name.hasPrefix("Sprecher") }
}

public struct HSClip: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var track: String
    public var file: String
    public var start: Double
    public var offset: Double
    public var duration: Double
    public var gainDB: Double
    public var fadeIn: Double
    public var fadeOut: Double
    public var label: String

    enum CodingKeys: String, CodingKey {
        case id, track, file, start, offset, duration, label
        case gainDB = "gain_db", fadeIn = "fade_in", fadeOut = "fade_out"
    }

    public init(id: String, track: String, file: String, start: Double, offset: Double = 0, duration: Double, gainDB: Double = 0,
                fadeIn: Double = 0, fadeOut: Double = 0, label: String = "") {
        self.id = id
        self.track = track
        self.file = file
        self.start = start
        self.offset = offset
        self.duration = duration
        self.gainDB = gainDB
        self.fadeIn = fadeIn
        self.fadeOut = fadeOut
        self.label = label
    }

    public var end: Double { start + duration }
}

public struct HSTimeline: Codable, Hashable, Sendable {
    public var sampleRate: Int
    public var tracks: [HSTrack]
    public var clips: [HSClip]
    public var chapters: [HSChapterMark]

    enum CodingKeys: String, CodingKey { case sampleRate = "sample_rate", tracks, clips, chapters }

    public init(sampleRate: Int = 48000, tracks: [HSTrack] = [], clips: [HSClip] = [], chapters: [HSChapterMark] = []) {
        self.sampleRate = sampleRate
        self.tracks = tracks
        self.clips = clips
        self.chapters = chapters
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sampleRate = try c.decodeIfPresent(Int.self, forKey: .sampleRate) ?? 48000
        tracks = try c.decodeIfPresent([HSTrack].self, forKey: .tracks) ?? []
        clips = try c.decodeIfPresent([HSClip].self, forKey: .clips) ?? []
        chapters = try c.decodeIfPresent([HSChapterMark].self, forKey: .chapters) ?? []
    }

    public var duration: Double { clips.map(\.end).max() ?? 0 }

    /// Spuren in fester Reihenfolge: Erzähler, Sprecher, Musik, Geräusche, Atmo, Rest.
    public var orderedTracks: [HSTrack] {
        func rank(_ t: HSTrack) -> Int {
            switch t.name {
            case "Erzähler": return 0
            case "Musik": return 2
            case "Geräusche": return 3
            case "Atmo": return 4
            default: return t.isVoice ? 1 : 5
            }
        }
        return tracks.sorted { (rank($0), $0.name) < (rank($1), $1.name) }
    }

    public func clips(on track: String) -> [HSClip] { clips.filter { $0.track == track }.sorted { $0.start < $1.start } }

    /// Hörbar (Stummschalten/Solo wie im Mischer).
    public func audible(_ track: String) -> Bool {
        guard let t = tracks.first(where: { $0.name == track }), !t.mute else { return false }
        let solos = tracks.filter(\.solo)
        return solos.isEmpty || t.solo
    }

    // MARK: Bearbeiten

    public mutating func move(_ id: String, to start: Double) {
        guard let i = clips.firstIndex(where: { $0.id == id }) else { return }
        clips[i].start = max(0, (start * 100).rounded() / 100)
    }

    /// Clip an einer Zeit (Sekunden auf der Zeitleiste) teilen. Liefert die Kennung des zweiten Teils.
    @discardableResult
    public mutating func split(_ id: String, at time: Double) -> String? {
        guard let i = clips.firstIndex(where: { $0.id == id }) else { return nil }
        let c = clips[i]
        let cut = time - c.start
        guard cut > 0.05, cut < c.duration - 0.05 else { return nil }
        var second = c
        second.id = uniqueID(c.id + "-b")
        second.start = time
        second.offset = c.offset + cut
        second.duration = c.duration - cut
        second.fadeIn = 0
        clips[i].duration = cut
        clips[i].fadeOut = 0
        clips.insert(second, at: i + 1)
        return second.id
    }

    public mutating func remove(_ id: String) { clips.removeAll { $0.id == id } }

    public mutating func update(_ id: String, _ change: (inout HSClip) -> Void) {
        guard let i = clips.firstIndex(where: { $0.id == id }) else { return }
        change(&clips[i])
        clips[i].fadeIn = max(0, min(clips[i].fadeIn, clips[i].duration))
        clips[i].fadeOut = max(0, min(clips[i].fadeOut, clips[i].duration - clips[i].fadeIn))
        clips[i].gainDB = max(-40, min(12, clips[i].gainDB))
    }

    public mutating func setTrack(_ name: String, _ change: (inout HSTrack) -> Void) {
        guard let i = tracks.firstIndex(where: { $0.name == name }) else { return }
        change(&tracks[i])
        tracks[i].gainDB = max(-40, min(12, tracks[i].gainDB))
    }

    /// Alles ab einer Zeit verschieben (z. B. Szenenübergang verlängern oder kürzen).
    public mutating func shift(from time: Double, by delta: Double) {
        for i in clips.indices where clips[i].start >= time { clips[i].start = max(0, clips[i].start + delta) }
        for i in chapters.indices where chapters[i].start >= time { chapters[i].start = max(0, chapters[i].start + delta) }
    }

    private func uniqueID(_ base: String) -> String {
        var id = base
        var n = 2
        while clips.contains(where: { $0.id == id }) { id = "\(base)\(n)"; n += 1 }
        return id
    }
}
