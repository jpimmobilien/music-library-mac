import Foundation
import AVFoundation
import MediaPlayer
import AppKit
import MLCore
import MLStore

/// Wiedergabeposition – eigenes Objekt, damit die häufigen Aktualisierungen nur die Fortschrittsanzeigen neu zeichnen.
@MainActor
final class PlaybackClock: ObservableObject {
    @Published var positionMs: Int64 = 0
    @Published var durationMs: Int64 = 0
    /// Restzeit des Sleep-Timers (nur bei laufendem Minuten-Timer) – hier statt im PlayerService, damit die
    /// sekündliche Aktualisierung nur die Anzeigen neu zeichnet, die sie wirklich zeigen.
    @Published var sleepRemainingMs: Int64?
}

/// Wiedergabe (Android: PlaybackService + PlaybackController + PlaybackHub).
///
/// Warteschlange und Regeln stammen aus MLCore (`PlayQueue`, `PlayCountRule`, `PreviousRule`, `ResumeRule`,
/// `SleepTimerLogic`) – dieselben Regeln wie unter Android, mit Unit-Tests. Die Klangkette ist `AudioEngine`.
@MainActor
final class PlayerService: ObservableObject {
    weak var model: AppModel?
    let store: LibraryStore
    let demo: Bool
    let clock = PlaybackClock()
    private(set) lazy var engine = AudioEngine()

    @Published private(set) var queue = PlayQueue()
    @Published private(set) var current: Track? {
        didSet {
            if current?.coverKey != oldValue?.coverKey {
                CoverAmbience.shared.update(for: current, enabled: model?.settings.dynamicCoverColors ?? true)
            }
        }
    }
    @Published private(set) var isPlaying = false
    @Published private(set) var sleepTimer: SleepTimerState?
    /// Restzeit des Sleep-Timers (Anzeige über `clock.sleepRemainingMs` beobachten).
    var sleepRemainingMs: Int64? { clock.sleepRemainingMs }
    @Published private(set) var lastError: String?
    /// Eine Ogg-Datei wird gerade für die Wiedergabe umgewandelt.
    @Published private(set) var preparing = false
    /// Ogg-Dateien, die sich nicht umwandeln ließen (kein erneuter Versuch in dieser Sitzung).
    private var oggFailures: Set<String> = []
    /// Lautstärke wird beim Ziehen sofort übernommen (gespeichert erst beim Loslassen).
    @Published var liveVolume: Float = 1

    var shuffleEnabled: Bool { queue.shuffleEnabled }
    var repeatMode: RepeatSetting { queue.repeatMode }

    private var file: AVAudioFile?
    private var segmentStartFrame: AVAudioFramePosition = 0
    private var pausedPositionMs: Int64 = 0
    private var generation = 0
    private var tickTimer: Timer?
    private var session: PlaySession?
    private var consecutiveFailures = 0
    private var lastSave: TimeInterval = 0
    private var effects = AudioEffectsSettings()
    private var pitch = PitchSettings()
    private var observers: [NSObjectProtocol] = []
    private var resumePoints: [Int64: ResumePoint] = [:]
    private var visualizerOn = false
    /// Anzahl sichtbarer Pegelanzeigen (Balken, VU-Meter, Aurora, Studio Reel). Die Analyse läuft nur, wenn
    /// die Visualisierung eingeschaltet ist **und** mindestens eine Anzeige sichtbar ist – unabhängig von der
    /// Reihenfolge, in der SwiftUI Ansichten ein- und ausblendet.
    private var visualizerConsumers = 0
    /// Alben der Ansicht, aus der die Wiedergabe gestartet wurde (für „Zufall nach Alben“; nicht gespeichert).
    private var albumContext: [[Int64]]?

    init(store: LibraryStore, demo: Bool) {
        self.store = store
        self.demo = demo
        guard !demo else { return }
        // Inneres `[weak self]`: ein schwach erfasstes `self` eines Sendable-Closures darf (Swift < 6.2) nicht
        // in einem weiteren nebenläufigen Closure benutzt werden.
        observers.append(NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleConfigurationChange() }
        })
        resumePoints = (try? store.resumePoints()) ?? [:]
        setupRemoteCommands()
    }

    // MARK: - Zeit

    private static func monotonicMs() -> Int64 { Int64(ProcessInfo.processInfo.systemUptime * 1000) }
    private static func wallMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    /// Aktuelle Position in Millisekunden (aus der Wiedergabezeit des Players).
    var positionMs: Int64 {
        guard isPlaying, let f = file,
              let nodeTime = engine.player.lastRenderTime,
              let playerTime = engine.player.playerTime(forNodeTime: nodeTime) else { return pausedPositionMs }
        let frame = segmentStartFrame + max(0, playerTime.sampleTime)
        let ms = Int64(Double(frame) / f.processingFormat.sampleRate * 1000)
        return min(ms, clock.durationMs > 0 ? clock.durationMs : ms)
    }

    // MARK: - Einstellungen

    func applyAudioSettings(effects: AudioEffectsSettings, pitch: PitchSettings) {
        self.effects = effects
        self.pitch = pitch
        liveVolume = effects.volume
        guard !demo else { return }
        pushEngineParameters()
    }

    /// Lautstärke während des Ziehens (ohne Speichern).
    func setLiveVolume(_ v: Float) {
        let upper = min(AudioEffectsSettings.maxVolume, max(1, model?.settings.maxVolume ?? AudioEffectsSettings.maxVolume))
        liveVolume = min(max(v, AudioEffectsSettings.minVolume), upper)
        guard !demo else { return }
        pushEngineParameters()
    }

    private func pushEngineParameters() {
        var p = AudioEngine.Parameters()
        p.bandGains = effects.effectiveBands
        p.bandFrequencies = EqBands.frequencies
        // Q → Bandbreite in Oktaven
        let q = EqBands.q
        p.bandwidth = Float(2 / log(2.0) * asinh(1 / (2 * q)))
        p.bassDb = effects.effectiveBassDb
        p.bassFrequency = Float(AudioEffectsSettings.bassFrequency)
        p.headroomDb = effects.headroomDb
        p.volume = liveVolume * sleepFade
        switch pitch.mode {
        case .key:
            p.pitchCents = pitch.pitchCents
            p.tempo = pitch.tempo
            p.varispeed = 1
        case .varispeed:
            p.pitchCents = 0
            p.tempo = 1
            p.varispeed = pitch.factor
        }
        engine.apply(p)
    }

    private var sleepFade: Float = 1

    func setVisualizer(_ on: Bool) {
        visualizerOn = on
        updateMeter()
    }

    /// Eine Pegelanzeige wird sichtbar (paarweise mit `releaseVisualizer()` aufrufen).
    func retainVisualizer() {
        visualizerConsumers += 1
        updateMeter()
    }

    func releaseVisualizer() {
        visualizerConsumers = max(0, visualizerConsumers - 1)
        updateMeter()
    }

    private func updateMeter() {
        guard !demo else { return }
        let on = visualizerOn && visualizerConsumers > 0
        guard engine.levels.enabled != on else { return }
        engine.levels.enabled = on
        if !on { engine.levels.reset() }
    }

    // MARK: - Abspielen

    /// Neue Warteschlange (Android `playTracks`). `startIndex == nil` + `.on` = gemischt ab zufälligem Titel.
    /// - Parameter albumContext: Alben der Ansicht, aus der gestartet wurde (Reihenfolge wie angezeigt). Wird später
    ///   „Zufall“ eingeschaltet, mischt die Wiedergabe nach Alben über diese Alben (v2.1, wie iTunes).
    func play(uids: [Int64], startIndex: Int?, shuffle: ShuffleStart, source: PlaybackSource, albumContext: [[Int64]]? = nil) {
        self.albumContext = albumContext
        let available = uids.filter { model?.track($0)?.available ?? false }
        guard !available.isEmpty else {
            model?.toast("Keine verfügbaren Titel – ist das Laufwerk angeschlossen?", isError: true)
            return
        }
        // Startindex auf die verfügbaren Titel umrechnen
        var start: Int? = nil
        if let s = startIndex, s >= 0, s < uids.count {
            let uid = uids[s]
            start = available.firstIndex(of: uid) ?? available.firstIndex { _ in true }
        }
        finishSession(finished: false)
        queue.replace(with: available, startIndex: start, shuffle: shuffle, source: source)
        loadCurrent(at: nil, autoplay: true)
    }

    func togglePlay() {
        if isPlaying { pause() } else { resume() }
    }

    func resume() {
        guard !demo else { return }
        guard current != nil else {
            if let first = model?.trackList.first?.uid { play(uids: [first], startIndex: 0, shuffle: .off, source: PlaybackSource(kind: .list, label: "Alle Titel")) }
            return
        }
        if file == nil {
            loadCurrent(at: pausedPositionMs, autoplay: true)
            return
        }
        do {
            try engine.start()
            engine.player.play()
            isPlaying = true
            session?.setPlaying(true, nowMonotonic: Self.monotonicMs())
            startTicking()
            updateNowPlaying()
        } catch {
            report("Audioausgabe nicht verfügbar: \(error.localizedDescription)")
        }
    }

    func pause() {
        guard isPlaying else { return }
        pausedPositionMs = positionMs
        engine.player.pause()
        isPlaying = false
        session?.setPlaying(false, nowMonotonic: Self.monotonicMs())
        clock.positionMs = pausedPositionMs
        saveState()
        updateNowPlaying()
    }

    func stop() {
        pausedPositionMs = positionMs
        generation += 1
        engine.stopPlayer()
        isPlaying = false
        session?.setPlaying(false, nowMonotonic: Self.monotonicMs())
        saveState()
        updateNowPlaying()
    }

    func next() {
        guard !queue.isEmpty else { return }
        finishSession(finished: false)
        if queue.skipToNext() {
            loadCurrent(at: nil, autoplay: isPlaying || file == nil)
        } else {
            // Ende ohne Wiederholung: anhalten am Ende
            stop()
        }
    }

    func previous() {
        guard !queue.isEmpty else { return }
        switch queue.previous(positionMs: positionMs) {
        case .restartCurrent:
            seek(to: 0)
        case .movedToPrevious:
            finishSession(finished: false)
            loadCurrent(at: 0, autoplay: isPlaying)
        case .none:
            break
        }
    }

    func seek(to ms: Int64) {
        guard file != nil else {
            pausedPositionMs = ms
            clock.positionMs = ms
            return
        }
        let wasPlaying = isPlaying
        generation += 1
        engine.stopPlayer()
        schedule(from: ms)
        pausedPositionMs = ms
        clock.positionMs = ms
        if wasPlaying {
            engine.player.play()
        }
        updateNowPlaying()
    }

    func skip(by seconds: Double) {
        let target = max(0, min(clock.durationMs, positionMs + Int64(seconds * 1000)))
        seek(to: target)
    }

    /// Sprungweite laut Einstellung (5, 10, 15 oder 30 Sekunden).
    var skipSeconds: Int { model?.settings.skipSeconds ?? 10 }

    func skipForward() { skip(by: Double(skipSeconds)) }

    func skipBackward() { skip(by: -Double(skipSeconds)) }

    /// Medientasten und Kontrollzentrum ein-/ausschalten (Einstellung „Medientasten verwenden“).
    func setMediaKeysEnabled(_ on: Bool) {
        let c = MPRemoteCommandCenter.shared()
        for cmd in [c.playCommand, c.pauseCommand, c.togglePlayPauseCommand, c.nextTrackCommand, c.previousTrackCommand,
                    c.changePlaybackPositionCommand, c.skipForwardCommand, c.skipBackwardCommand] as [MPRemoteCommand] {
            cmd.isEnabled = on
        }
    }

    /// Zufall ein/aus (Mini-Player, großer Player, Menü, Kontrollzentrum – alle lesen denselben Zustand).
    /// Wurde aus der Alben-Ansicht gestartet, wird beim Einschalten nach Alben gemischt: das laufende Album
    /// spielt zu Ende, danach folgen die übrigen Alben der Ansicht in Zufallsfolge, jedes in Titelreihenfolge.
    /// Die Wiedergabe wird dabei nicht neu gestartet.
    func toggleShuffle() {
        let enable = !queue.shuffleEnabled
        if enable, !queue.isAlbumShuffle, let ctx = albumContext, let cur = queue.currentTrackUid, ctx.count > 1,
           ctx.contains(where: { $0.contains(cur) }) {
            let available = ctx.map { album in album.filter { model?.track($0)?.available ?? false } }
            queue.replaceAlbums(available, currentTrackUid: cur, shuffle: true, source: queue.source)
        } else {
            queue.setShuffle(enable)
        }
        saveState()
    }

    /// „Alben mischen“: zufälliges erstes Album, danach weitere Alben in Zufallsfolge, jedes in Titelreihenfolge.
    func shuffleAlbums(_ albums: [[Int64]], source: PlaybackSource) {
        let available = albums.map { album in album.filter { model?.track($0)?.available ?? false } }.filter { !$0.isEmpty }
        guard !available.isEmpty else {
            model?.toast("Keine verfügbaren Titel – ist das Laufwerk angeschlossen?", isError: true)
            return
        }
        albumContext = albums
        finishSession(finished: false)
        queue.replaceAlbums(available, currentTrackUid: nil, shuffle: true, source: source)
        loadCurrent(at: nil, autoplay: true)
    }

    /// Zufall nach Alben aktiv (Anzeige „Alben gemischt“).
    var isAlbumShuffle: Bool { queue.isAlbumShuffle }

    func cycleRepeat() {
        queue.cycleRepeat()
        saveState()
    }

    func setRepeat(_ mode: RepeatSetting) {
        queue.repeatMode = mode
        saveState()
    }

    // MARK: - Warteschlange

    func playNext(uids: [Int64]) {
        guard !uids.isEmpty else { return }
        if queue.isEmpty {
            play(uids: uids, startIndex: 0, shuffle: .off, source: PlaybackSource(kind: .list, label: "Warteschlange"))
            return
        }
        _ = queue.playNext(uids)
        model?.toast(uids.count == 1 ? "Wird als Nächstes gespielt" : "\(Formatting.tracks(uids.count)) werden als Nächstes gespielt")
        saveState()
    }

    func addToQueue(uids: [Int64]) {
        guard !uids.isEmpty else { return }
        if queue.isEmpty {
            play(uids: uids, startIndex: 0, shuffle: .off, source: PlaybackSource(kind: .list, label: "Warteschlange"))
            return
        }
        _ = queue.addToEnd(uids)
        model?.toast("\(Formatting.tracks(uids.count)) zur Warteschlange hinzugefügt")
        saveState()
    }

    func jump(to item: PlayQueue.Item) {
        finishSession(finished: false)
        if queue.jump(toItemID: item.id) { loadCurrent(at: 0, autoplay: true) }
    }

    func removeFromQueue(item: PlayQueue.Item) {
        handle(queue.remove(itemID: item.id))
    }

    func removeFromQueue(uids: [Int64]) {
        let set = Set(uids)
        handle(queue.removeAll { set.contains($0.trackUid) })
    }

    func moveUpNext(from: Int, to: Int) {
        _ = queue.moveUpNext(from: from, to: to)
        saveState()
    }

    func clearUpNext() {
        let upcoming = Set(queue.upNext.map(\.id))
        handle(queue.removeAll { upcoming.contains($0.id) })
    }

    private func handle(_ change: PlayQueue.CurrentChange) {
        switch change {
        case .unchanged: break
        case .changed(let continuePlayback):
            finishSession(finished: false)
            loadCurrent(at: 0, autoplay: continuePlayback && isPlaying)
        case .emptied:
            finishSession(finished: false)
            generation += 1
            if !demo { engine.stopPlayer() }
            file = nil
            current = nil
            isPlaying = false
            clock.positionMs = 0
            clock.durationMs = 0
            model?.playerOpen = false
            updateNowPlaying()
        }
        saveState()
    }

    /// Nach Änderungen der Bibliothek: Titelangaben aktualisieren, nicht mehr vorhandene Titel entfernen.
    func libraryChanged() {
        guard let model else { return }
        if let c = current, let fresh = model.track(c.uid) {
            current = fresh
            updateNowPlaying()
        }
        let missing = queue.items.map(\.trackUid).filter { model.track($0) == nil }
        if !missing.isEmpty { removeFromQueue(uids: missing) }
    }

    // MARK: - Laden und Planen

    private func loadCurrent(at position: Int64?, autoplay: Bool) {
        guard let uid = queue.currentTrackUid, let track = model?.track(uid) else {
            handle(.emptied)
            return
        }
        current = track
        clock.durationMs = track.durationMs
        lastError = nil
        guard !demo else {
            pausedPositionMs = position ?? 0
            clock.positionMs = pausedPositionMs
            isPlaying = autoplay
            return
        }
        // Lange Titel: gemerkte Position fortsetzen
        var start = position ?? 0
        if position == nil, model?.settings.rememberLongTrackPosition ?? true,
           ResumeRule.isLongTrack(durationMs: track.durationMs), let point = resumePoints[uid] {
            start = point.positionMs
            model?.toast("Fortgesetzt bei \(Formatting.duration(start))")
        }
        generation += 1
        engine.stopPlayer()
        guard engine.hasOutputDevice else {
            file = nil
            isPlaying = false
            report("Kein Audio-Ausgabegerät gefunden – bitte Lautsprecher oder Kopfhörer anschließen.")
            saveState()
            updateNowPlaying()
            return
        }
        let sourceURL = URL(fileURLWithPath: track.path)
        var playURL = sourceURL
        if OggTranscoder.isOgg(sourceURL) && !oggFailures.contains(track.path) {
            if let decoded = OggTranscoder.cached(for: sourceURL) {
                playURL = decoded
            } else {
                // Ogg Vorbis einmalig umwandeln (im Hintergrund), danach erneut laden
                isPlaying = false
                preparing = true
                model?.toast("Ogg-Datei wird für die Wiedergabe vorbereitet …")
                let gen = generation
                let path = track.path
                Task.detached(priority: .userInitiated) { [weak self] in
                    let ok = (try? OggTranscoder.decode(sourceURL)) != nil
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        self.preparing = false
                        guard self.generation == gen else { return }
                        if !ok { self.oggFailures.insert(path) }
                        self.loadCurrent(at: position, autoplay: autoplay)
                    }
                }
                return
            }
        }
        do {
            let f = try AVAudioFile(forReading: playURL)
            file = f
            engine.connect(format: f.processingFormat)
            try engine.start()
            pushEngineParameters()
            let fileDuration = Int64(Double(f.length) / f.processingFormat.sampleRate * 1000)
            if fileDuration > 0 { clock.durationMs = fileDuration }
            schedule(from: start)
            pausedPositionMs = start
            clock.positionMs = start
            if autoplay {
                engine.player.play()
                isPlaying = true
            } else {
                isPlaying = false
            }
            consecutiveFailures = 0
            session = PlaySession(trackUid: uid, startedAt: Self.wallMs(), nowMonotonic: Self.monotonicMs(), playing: autoplay)
            startTicking()
        } catch {
            file = nil
            isPlaying = false
            let ext = track.fileExtension
            let reason: String
            if !FileManager.default.fileExists(atPath: track.path) {
                reason = "Datei nicht gefunden"
            } else if ext == "opus" {
                reason = "Opus-Dateien kann diese Version noch nicht abspielen"
            } else if ext == "ogg" || ext == "oga" {
                reason = "Nur Ogg Vorbis wird unterstützt (nicht Ogg Opus/FLAC)"
            } else {
                reason = "Format wird nicht unterstützt"
            }
            report("„\(track.displayTitle)“: \(reason)")
            consecutiveFailures += 1
            // Nächsten Titel versuchen (aber nicht endlos)
            if autoplay, consecutiveFailures < 5, queue.skipToNext() {
                loadCurrent(at: nil, autoplay: true)
                return
            }
        }
        saveState()
        updateNowPlaying()
    }

    private func schedule(from ms: Int64) {
        guard let f = file else { return }
        let gen = generation
        let sr = f.processingFormat.sampleRate
        let start = max(0, min(AVAudioFramePosition(Double(ms) / 1000 * sr), f.length))
        segmentStartFrame = start
        let frames = AVAudioFrameCount(max(0, f.length - start))
        guard frames > 0 else {
            DispatchQueue.main.async { [weak self] in self?.segmentFinished(gen) }
            return
        }
        engine.player.scheduleSegment(f, startingFrame: start, frameCount: frames, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.segmentFinished(gen) }
        }
    }

    /// Ende des Titels erreicht (nicht beim Stoppen/Springen – dafür sorgt `generation`).
    private func segmentFinished(_ gen: Int) {
        guard gen == generation, file != nil else { return }
        finishSession(finished: true)
        if let timer = sleepTimer, timer.endOfTrack {
            cancelSleepTimer()
            stop()
            pausedPositionMs = 0
            seekWithoutPlaying(0)
            model?.toast("Sleep-Timer: Wiedergabe beendet")
            return
        }
        switch queue.advanceAfterCompletion() {
        case .repeatCurrent:
            loadCurrent(at: 0, autoplay: true)
        case .advanced:
            loadCurrent(at: 0, autoplay: true)
        case .endOfQueue:
            isPlaying = false
            seekWithoutPlaying(0)
            saveState()
            updateNowPlaying()
        case .none:
            isPlaying = false
        }
    }

    private func seekWithoutPlaying(_ ms: Int64) {
        guard file != nil else { return }
        generation += 1
        engine.stopPlayer()
        schedule(from: ms)
        pausedPositionMs = ms
        clock.positionMs = ms
    }

    private func handleConfigurationChange() {
        // Ausgabegerät gewechselt (z. B. Kopfhörer): Kette neu starten, Position halten
        let pos = positionMs
        let wasPlaying = isPlaying
        isPlaying = false
        guard file != nil else { return }
        generation += 1
        engine.stopPlayer()
        do {
            try engine.start()
            schedule(from: pos)
            pausedPositionMs = pos
            if wasPlaying {
                engine.player.play()
                isPlaying = true
            }
        } catch {
            report("Audioausgabe wurde gewechselt und konnte nicht neu gestartet werden.")
        }
    }

    private func report(_ message: String) {
        lastError = message
        model?.toast(message, isError: true)
    }

    // MARK: - Statistik, Verlauf, gemerkte Positionen

    private func finishSession(finished: Bool) {
        guard let s = session, !demo else {
            session = nil
            return
        }
        session = nil
        let now = Self.monotonicMs()
        let listened = s.listened(nowMonotonic: now)
        let duration = clock.durationMs
        let privacyHistory = model?.settings.recordHistory ?? true
        let privacyCounts = model?.settings.recordPlayCounts ?? true
        let addHistory = privacyHistory && HistoryRule.shouldRecord(listenedMs: listened, durationMs: duration, counted: s.counted)
        if privacyHistory || privacyCounts {
            try? store.finishPlayback(trackUid: s.trackUid, startedAt: s.startedAt, listenedMs: listened,
                                      counted: s.counted && privacyCounts, addToHistory: addHistory)
        }
        // Gemerkte Position langer Titel
        if ResumeRule.isLongTrack(durationMs: duration), model?.settings.rememberLongTrackPosition ?? true {
            switch ResumeRule.update(positionMs: finished ? duration : positionMs, durationMs: duration, finished: finished) {
            case .save(let p):
                try? store.setResumePoint(trackUid: s.trackUid, positionMs: p)
                resumePoints[s.trackUid] = ResumePoint(trackUid: s.trackUid, positionMs: p, updatedAt: Self.wallMs())
            case .clear:
                try? store.setResumePoint(trackUid: s.trackUid, positionMs: nil)
                resumePoints[s.trackUid] = nil
            case .keep:
                break
            }
        }
        model?.playbackRecorded()
    }

    private func startTicking() {
        guard tickTimer == nil else { return }
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        tickTimer = t
    }

    private func tick() {
        let pos = positionMs
        if clock.positionMs != pos { clock.positionMs = pos }
        // Wiedergabe zählen, sobald die Regel erfüllt ist
        if var s = session {
            let before = s.counted
            _ = s.countIfDue(nowMonotonic: Self.monotonicMs(), nowWall: Self.wallMs(), durationMs: clock.durationMs, stats: nil)
            if s.counted && !before && (model?.settings.recordPlayCounts ?? true) {
                try? store.countPlay(trackUid: s.trackUid, at: Self.wallMs())
                model?.playbackRecorded()
            }
            session = s
        }
        tickSleepTimer()
        let now = ProcessInfo.processInfo.systemUptime
        if isPlaying, now - lastSave > 10 {
            lastSave = now
            saveState()
        }
        if !isPlaying && sleepTimer == nil, let timer = tickTimer {
            timer.invalidate()
            tickTimer = nil
        }
    }

    // MARK: - Sleep-Timer

    func startSleepTimer(minutes: Int) {
        sleepTimer = SleepTimerLogic.start(nowElapsed: Self.monotonicMs(), minutes: minutes)
        startTicking()
        tickSleepTimer()
        model?.toast("Sleep-Timer: \(minutes) min")
    }

    func sleepAtEndOfTrack() {
        sleepTimer = SleepTimerLogic.endOfTrack()
        if clock.sleepRemainingMs != nil { clock.sleepRemainingMs = nil }
        model?.toast("Sleep-Timer: am Ende des Titels")
    }

    func cancelSleepTimer() {
        sleepTimer = nil
        if clock.sleepRemainingMs != nil { clock.sleepRemainingMs = nil }
        if sleepFade != 1 {
            sleepFade = 1
            if !demo { pushEngineParameters() }
        }
    }

    private func tickSleepTimer() {
        guard let state = sleepTimer, !state.endOfTrack else { return }
        let now = Self.monotonicMs()
        let remaining = SleepTimerLogic.remainingMs(state, nowElapsed: now)
        // nur volle Sekunden melden (weniger Neuzeichnen)
        let shownSeconds: Int64? = clock.sleepRemainingMs.map { $0 / 1000 }
        let newSeconds: Int64? = remaining.map { $0 / 1000 }
        if shownSeconds != newSeconds { clock.sleepRemainingMs = remaining }
        if SleepTimerLogic.isExpired(state, nowElapsed: now) {
            pause()
            cancelSleepTimer()
            model?.toast("Sleep-Timer: Wiedergabe angehalten")
            return
        }
        let fade: Float = (model?.settings.sleepTimerFadeOut ?? true) ? SleepTimerLogic.fadeFactor(state, nowElapsed: now) : 1
        if fade != sleepFade {
            sleepFade = fade
            if !demo { pushEngineParameters() }
        }
    }

    // MARK: - Zustand sichern und wiederherstellen

    private static let stateKey = "playback.state"

    func saveState() {
        guard !demo else { return }
        let state = SavedPlaybackState(queue: queue, positionMs: positionMs, savedAt: Self.wallMs())
        if let data = try? JSONEncoder().encode(state), let text = String(data: data, encoding: .utf8) {
            store.setStateValue(text, for: Self.stateKey)
        }
    }

    /// Beim Start: Warteschlange und Position wiederherstellen (pausiert).
    func restoreState() {
        guard !demo, let model else { return }
        let saved = store.stateValue(Self.stateKey).flatMap { $0.data(using: .utf8) }.flatMap { try? JSONDecoder().decode(SavedPlaybackState.self, from: $0) }
        guard let state = ResumeRule.restoreOnLaunch(saved, enabled: model.settings.resumeOnLaunch,
                                                      isAvailable: { model.track($0)?.available ?? false },
                                                      durationOf: { model.track($0)?.durationMs }) else { return }
        queue = state.queue
        loadCurrent(at: state.positionMs, autoplay: false)
    }

    // MARK: - Systemsteuerung (Mediatasten, Kontrollzentrum, Kopfhörer)

    private func setupRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in Task { @MainActor [weak self] in self?.resume() }; return .success }
        c.pauseCommand.addTarget { [weak self] _ in Task { @MainActor [weak self] in self?.pause() }; return .success }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor [weak self] in self?.togglePlay() }; return .success }
        c.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor [weak self] in self?.next() }; return .success }
        c.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor [weak self] in self?.previous() }; return .success }
        c.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let ms = Int64(e.positionTime * 1000)
            Task { @MainActor [weak self] in self?.seek(to: ms) }
            return .success
        }
        updateSkipInterval()
        c.skipForwardCommand.addTarget { [weak self] _ in Task { @MainActor [weak self] in self?.skipForward() }; return .success }
        c.skipBackwardCommand.addTarget { [weak self] _ in Task { @MainActor [weak self] in self?.skipBackward() }; return .success }
    }

    /// Sprungweite für Kontrollzentrum/Touch Bar aus der Einstellung „Sprungweite“.
    func updateSkipInterval() {
        let c = MPRemoteCommandCenter.shared()
        c.skipForwardCommand.preferredIntervals = [NSNumber(value: skipSeconds)]
        c.skipBackwardCommand.preferredIntervals = [NSNumber(value: skipSeconds)]
    }

    private var nowPlayingArtworkKey: String?

    func updateNowPlaying() {
        guard !demo else { return }
        let center = MPNowPlayingInfoCenter.default()
        guard let t = current else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: t.displayTitle,
            MPMediaItemPropertyArtist: t.artistText ?? "",
            MPMediaItemPropertyAlbumTitle: t.album ?? "",
            MPMediaItemPropertyPlaybackDuration: Double(clock.durationMs) / 1000,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: Double(positionMs) / 1000,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? engine.effectiveRate : 0,
        ]
        if let old = center.nowPlayingInfo, nowPlayingArtworkKey == t.coverKey, let art = old[MPMediaItemPropertyArtwork] {
            info[MPMediaItemPropertyArtwork] = art
        }
        center.nowPlayingInfo = info
        center.playbackState = isPlaying ? .playing : .paused
        if nowPlayingArtworkKey != t.coverKey {
            nowPlayingArtworkKey = t.coverKey
            Task { [weak self] in
                guard let image = await ArtworkStore.shared.image(for: t, size: .medium) else { return }
                await MainActor.run { [weak self] in
                    guard let self, self.current?.uid == t.uid else { return }
                    var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                    info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
                }
            }
        }
    }

    // MARK: - Demo (Vorschaubilder)

    /// Setzt einen Wiedergabezustand ohne Audio (Snapshot-Modus).
    func setDemoState(queueUids: [Int64], currentIndex: Int, positionMs: Int64, playing: Bool) {
        queue.replace(with: queueUids, startIndex: currentIndex, shuffle: .off, source: PlaybackSource(kind: .list, label: "Demo"))
        loadCurrent(at: positionMs, autoplay: playing)
    }

    /// Wird beim Beenden aufgerufen.
    func shutdown() {
        finishSession(finished: false)
        saveState()
    }
}
