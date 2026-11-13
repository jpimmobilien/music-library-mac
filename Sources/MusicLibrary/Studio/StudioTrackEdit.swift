import Foundation
import MLCore
import MLStudio
import StudioEngine

// „Titel bearbeiten“ (2.3): Titel der Bibliothek dauerhaft verändern – Lautstärke, Tempo, Tonhöhe, Stimmung
// (Kammerton), Equalizer, Auto-Tune, automatische Verbesserung und Beschneiden. Gespeichert wird über die
// Warteschlange wie beim Schneiden: Original ersetzen (Sicherung, Bestätigung, „Rückgängig“) oder neue Datei.

extension StudioModel {
    /// Wirksame Bearbeitung für den Export (nil = nur Schnitt/Blenden bzw. nicht im Bearbeitungsmodus).
    var activeTrackEdit: TrackEdit? {
        guard mode == .edit, isLibraryTrack, !trackEdit.isNeutral else { return nil }
        return trackEdit.normalized()
    }

    /// Bearbeitung beim Vorhören (nil = Original).
    var previewEditSettings: TrackEdit? {
        guard mode == .edit, previewEdited, !trackEdit.isNeutral else { return nil }
        return trackEdit.normalized()
    }

    /// Verstärkung für „Lautheit angleichen“ beim Vorhören (aus der Analyse des Originals; der Export misst genau).
    var previewNormalizationGain: Double? {
        guard trackEdit.enhance, trackEdit.normalize else { return nil }
        return trackEdit.normalizationGain(measured: trackAnalysis?.loudness)
    }

    /// Länge nach Schnitt und Tempoänderung.
    var editedDuration: Double {
        let base = effectiveTrim?.length ?? duration
        return mode == .edit ? trackEdit.normalized().outputDuration(base) : base
    }

    // MARK: Öffnen und Schließen

    /// Titel der Bibliothek zum Bearbeiten öffnen (Kontextmenü „Titel bearbeiten …“).
    func openTrackEditor(_ uid: Int64) {
        if source?.libraryUid == uid, sourceState == .ready {
            lib?.studioShow()
            enterEditMode()
            return
        }
        opensInEditMode = true
        openLibraryTrack(uid)
    }

    /// Bearbeitungsmodus für den geladenen Bibliothekstitel. Standard: Original ersetzen (dauerhaft).
    func enterEditMode() {
        guard isLibraryTrack else { return }
        mode = .edit
        if source?.sameFormat != nil {
            keepOriginalFormat = true
            cutSaveMode = .replaceOriginal
        }
        if trackAnalysis == nil { startTrackAnalysis() }
        pushPreviewEdit(immediately: true)
    }

    /// Zurück zum Schneiden (Einstellungen bleiben, bis eine andere Quelle geladen wird).
    func leaveEditMode() {
        mode = .convert
        pushPreviewEdit(immediately: true)
    }

    /// Beim Laden einer neuen Quelle.
    func resetTrackEditState() {
        trackAnalysisTask?.cancel()
        trackAnalysisTask = nil
        previewEditTask?.cancel()
        previewEditTask = nil
        trackAnalysis = nil
        trackAnalysisProgress = nil
        tuningTouched = false
        keyTouched = false
        if trackEdit != TrackEdit() { trackEdit = TrackEdit() }
        previewEdited = true
        if mode != .convert { mode = .convert }
        preview?.setEdit(nil, normalizationGainDb: nil)
    }

    /// Alle Klangänderungen zurücksetzen (Stimmung bleibt auf dem erkannten Kammerton).
    func resetTrackEdit() {
        var e = TrackEdit()
        if let ref = trackAnalysis?.reference, (trackAnalysis?.referenceConfidence ?? 0) >= 0.3 {
            e.tuningFrom = Self.roundedReference(ref)
            e.tuningTo = e.tuningFrom
        }
        if let k = trackAnalysis?.keyTonic, let sc = trackAnalysis?.keyScale {
            e.autoTuneKey = k
            e.autoTuneScale = sc
        }
        tuningTouched = false
        keyTouched = false
        trackEdit = e
    }

    // MARK: Analyse

    func startTrackAnalysis() {
        guard let source, let file = source.localFile ?? (source.kind == .localFile ? source.url : nil) else { return }
        trackAnalysisTask?.cancel()
        trackAnalysisProgress = 0
        let generation = sourceGeneration
        let analyzer = services.editAnalyzer
        let throttle = ThrottleGate(interval: 0.2)
        trackAnalysisTask = Task { [weak self] in
            do {
                let result = try await analyzer.analyze(file) { value in
                    guard throttle.allow(force: value >= 1) else { return }
                    Task { @MainActor [weak self] in
                        guard let self, generation == self.sourceGeneration, self.trackAnalysis == nil else { return }
                        self.trackAnalysisProgress = value
                    }
                }
                guard let self, generation == self.sourceGeneration else { return }
                self.applyAnalysis(result)
            } catch {
                guard let self, generation == self.sourceGeneration else { return }
                self.trackAnalysisProgress = nil
                if !Self.isCancellation(error) { self.trackAnalysis = TrackAnalysis() }
            }
        }
    }

    /// Ergebnis übernehmen: Kammerton und Tonart als Ausgangswerte (solange der Nutzer sie nicht geändert hat).
    func applyAnalysis(_ result: TrackAnalysis) {
        trackAnalysis = result
        trackAnalysisProgress = nil
        var e = trackEdit
        if !tuningTouched, let ref = result.reference, result.referenceConfidence >= 0.3 {
            let r = Self.roundedReference(ref)
            // Ausgangswert: unverändert (von = nach); eine gewählte Zielstimmung bleibt erhalten
            let wasNeutral = e.isTuningNeutral
            e.tuningFrom = r
            if wasNeutral { e.tuningTo = r }
        }
        if !keyTouched, let k = result.keyTonic, let sc = result.keyScale, result.keyCorrelation >= 0.5 {
            e.autoTuneKey = k
            e.autoTuneScale = sc
        }
        if e != trackEdit { trackEdit = e }
        pushPreviewEdit(immediately: true)
    }

    nonisolated static func roundedReference(_ hz: Double) -> Double { (hz * 10).rounded() / 10 }

    // MARK: Änderungen

    func trackEditChanged() {
        guard mode == .edit else { return }
        pushPreviewEdit(immediately: false)
    }

    /// Vorhören an die Einstellungen anpassen (beim Ziehen eines Reglers verzögert, damit die Wiedergabe nicht ständig neu startet).
    func pushPreviewEdit(immediately: Bool) {
        previewEditTask?.cancel()
        let apply: @MainActor () -> Void = { [weak self] in
            guard let self else { return }
            self.preview?.setEdit(self.previewEditSettings, normalizationGainDb: self.previewNormalizationGain)
        }
        if immediately {
            apply()
            return
        }
        previewEditTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }
            apply()
        }
    }

    /// Zielstimmung (z. B. 432 Hz).
    func setTuningTarget(_ hz: Double) {
        tuningTouched = true
        trackEdit.tuningTo = min(max(hz, TrackEdit.tuningRange.lowerBound), TrackEdit.tuningRange.upperBound)
    }

    /// Ausgangsstimmung von Hand (falls die Erkennung danebenliegt).
    func setTuningSource(_ hz: Double) {
        tuningTouched = true
        trackEdit.tuningFrom = min(max(hz, TrackEdit.tuningRange.lowerBound), TrackEdit.tuningRange.upperBound)
    }

    /// Erkannte Tonart für Auto-Tune übernehmen.
    func applyDetectedKey() {
        guard let k = trackAnalysis?.keyTonic, let sc = trackAnalysis?.keyScale else { return }
        keyTouched = false
        trackEdit.autoTuneKey = k
        trackEdit.autoTuneScale = sc
    }

    func setAutoTuneKey(_ key: Int, scale: MusicScale) {
        keyTouched = true
        trackEdit.autoTuneKey = key
        trackEdit.autoTuneScale = scale
    }

    /// Equalizer und Bass wie im Player.
    func copyPlayerEqualizer() {
        guard let fx = lib?.studioPlayerEffects else { return }
        trackEdit.bandGains = fx.effectiveBands
        trackEdit.bassDb = fx.effectiveBassDb
    }

    var playerEqualizerAvailable: Bool {
        guard let fx = lib?.studioPlayerEffects else { return false }
        return !fx.isToneNeutral
    }

    func applyEqualizer(gains: [Float], bassDb: Float? = nil) {
        var e = trackEdit
        e.bandGains = gains
        if let bassDb { e.bassDb = bassDb }
        trackEdit = e.normalized()
    }

    var eqUserPresets: [EqUserPreset] { lib?.studioEqUserPresets ?? [] }
}
