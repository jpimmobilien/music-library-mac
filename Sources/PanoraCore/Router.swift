import Foundation

// =============================================================================================
// Model Router und Speicherplanung.
//
// AUTO: Für jede Anfrage werden alle installierten Modelle hart gefiltert (verfügbar, Kontextfenster,
// Fähigkeiten, Speicherbudget, Lizenz) und dann bewertet: erwartete Qualität für die Aufgabe, erwartetes
// Tempo, Ladezeit. Ein bereits arbeitendes Modell bleibt, solange es fast so gut ist (kein unnötiger Wechsel).
// MANUELL: Das gewählte Modell wird nie ersetzt. Ist es nicht nutzbar, meldet der Router das – mit einem
// Vorschlag, den der Nutzer bestätigen muss.
// =============================================================================================

public enum RoutingMode: String, Codable, Sendable, CaseIterable {
    case auto
    case manual

    public var label: String { self == .auto ? "Auto" : "Manuell" }
}

/// Zustand der Hardware zum Zeitpunkt der Entscheidung.
public struct HardwareSnapshot: Sendable, Equatable {
    public var totalMemory: Int64
    /// Sofort verfügbarer Arbeitsspeicher (frei + inaktiv + entfernbar).
    public var availableMemory: Int64
    /// Obergrenze, die Modelle zusammen belegen dürfen (Einstellung).
    public var modelBudget: Int64
    /// Speicherbandbreite in GB/s (bestimmt die Token-Rate).
    public var memoryBandwidthGBs: Double
    /// Lesegeschwindigkeit des Modell-Laufwerks in GB/s (bestimmt die Ladezeit).
    public var diskReadGBs: Double
    public var cpuLoad: Double
    public var gpuLoad: Double

    public init(totalMemory: Int64, availableMemory: Int64, modelBudget: Int64, memoryBandwidthGBs: Double = 273,
                diskReadGBs: Double = 1.5, cpuLoad: Double = 0, gpuLoad: Double = 0) {
        self.totalMemory = totalMemory
        self.availableMemory = availableMemory
        self.modelBudget = modelBudget
        self.memoryBandwidthGBs = memoryBandwidthGBs
        self.diskReadGBs = diskReadGBs
        self.cpuLoad = cpuLoad
        self.gpuLoad = gpuLoad
    }
}

public struct LoadedModel: Sendable, Equatable {
    public var id: String
    public var bytes: Int64
    public var lastUsed: Date

    public init(id: String, bytes: Int64, lastUsed: Date) {
        self.id = id
        self.bytes = bytes
        self.lastUsed = lastUsed
    }
}

public enum MemoryPlanner {
    /// Grundbedarf außerhalb von Gewichten und KV-Cache (Aktivierungen, Puffer).
    public static let overheadBytes: Int64 = 700_000_000

    /// Speicherbedarf eines Modells mit `contextTokens` im KV-Cache.
    public static func requiredBytes(for spec: ModelSpec, contextTokens: Int) -> Int64 {
        let weights = Int64(Double(spec.sizeBytes) * 1.04)
        let kv = Int64(spec.kvBytesPerTokenEstimate) * Int64(max(0, contextTokens))
        return weights + kv + overheadBytes
    }

    public struct Plan: Sendable, Equatable {
        public var fits: Bool
        /// Modelle, die vorher entladen werden (am längsten ungenutzt zuerst).
        public var unload: [String]
        public var required: Int64
        public var budget: Int64
        /// Belegung durch Modelle nach dem Laden.
        public var usedAfter: Int64
        public var alreadyLoaded: Bool
        public var reason: String?
    }

    public static func plan(for spec: ModelSpec, contextTokens: Int, loaded: [LoadedModel], hardware: HardwareSnapshot) -> Plan {
        let required = requiredBytes(for: spec, contextTokens: contextTokens)
        let budget = hardware.modelBudget
        // Spielraum durch Speicherkomprimierung des Systems (macOS lagert andere Apps aus).
        let slack = Int64(Double(hardware.totalMemory) * 0.08)
        if let existing = loaded.first(where: { $0.id == spec.id }) {
            let used = loaded.reduce(Int64(0)) { $0 + $1.bytes } - existing.bytes + required
            let fits = required <= budget
            return Plan(fits: fits, unload: [], required: required, budget: budget, usedAfter: used, alreadyLoaded: true,
                        reason: fits ? nil : "benötigt \(Formatting.bytes(required)), Budget \(Formatting.bytes(budget))")
        }
        var kept = loaded.sorted { $0.lastUsed < $1.lastUsed }
        var unload: [String] = []
        var freed: Int64 = 0
        func keptBytes() -> Int64 { kept.reduce(Int64(0)) { $0 + $1.bytes } }
        func ok() -> Bool {
            keptBytes() + required <= budget && required <= hardware.availableMemory + freed + slack
        }
        while !ok() && !kept.isEmpty {
            let victim = kept.removeFirst()
            unload.append(victim.id)
            freed += victim.bytes
        }
        let fits = ok()
        var reason: String?
        if !fits {
            if required > budget {
                reason = "benötigt \(Formatting.bytes(required)), Budget \(Formatting.bytes(budget))"
            } else {
                reason = "benötigt \(Formatting.bytes(required)), frei sind nur \(Formatting.bytes(hardware.availableMemory + freed))"
            }
        }
        return Plan(fits: fits, unload: fits ? unload : [], required: required, budget: budget,
                    usedAfter: keptBytes() + required, alreadyLoaded: false, reason: reason)
    }
}

public struct ModelCandidate: Sendable, Equatable {
    public var spec: ModelSpec
    public var available: Bool
    public var unavailableReason: String?
    /// Gemessene Token-Rate auf diesem Mac (falls bekannt).
    public var measuredTokensPerSecond: Double?

    public init(spec: ModelSpec, available: Bool = true, unavailableReason: String? = nil, measuredTokensPerSecond: Double? = nil) {
        self.spec = spec
        self.available = available
        self.unavailableReason = unavailableReason
        self.measuredTokensPerSecond = measuredTokensPerSecond
    }
}

public struct CandidateScore: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var quality: Double
    public var speed: Double
    public var total: Double
    public var tokensPerSecond: Double
    public var excluded: String?
    public var plan: MemoryPlanner.Plan?
}

public struct RoutingRequest: Sendable {
    public var profile: TaskProfile
    public var candidates: [ModelCandidate]
    public var hardware: HardwareSnapshot
    public var loaded: [LoadedModel]
    public var currentModelID: String?
    public var mode: RoutingMode
    public var pinnedModelID: String?
    public var allowSwitchInManual: Bool
    /// Tokens, die ins Kontextfenster müssen (Verlauf, Eingabe, Platz für die Antwort).
    public var neededContextTokens: Int
    /// Wie stark ein laufendes Modell bevorzugt wird (0 … 2).
    public var stickiness: Double

    public init(profile: TaskProfile, candidates: [ModelCandidate], hardware: HardwareSnapshot, loaded: [LoadedModel] = [],
                currentModelID: String? = nil, mode: RoutingMode = .auto, pinnedModelID: String? = nil,
                allowSwitchInManual: Bool = false, neededContextTokens: Int = 4096, stickiness: Double = 0.45) {
        self.profile = profile
        self.candidates = candidates
        self.hardware = hardware
        self.loaded = loaded
        self.currentModelID = currentModelID
        self.mode = mode
        self.pinnedModelID = pinnedModelID
        self.allowSwitchInManual = allowSwitchInManual
        self.neededContextTokens = neededContextTokens
        self.stickiness = stickiness
    }
}

public struct RoutingDecision: Sendable, Equatable {
    public var chosen: ModelSpec?
    /// Weicht vom Modell der letzten Antwort ab.
    public var switched: Bool
    public var previousModelID: String?
    /// Ein Satz für die Oberfläche.
    public var summary: String
    public var reasons: [String]
    public var plan: MemoryPlanner.Plan?
    public var scores: [CandidateScore]
    /// MANUELL: besser geeignetes Modell – nur nach Rückfrage.
    public var suggestion: ModelSpec?
    public var suggestionReason: String?
    /// Kein Modell möglich (mit Grund).
    public var failure: String?
    public var mode: RoutingMode
    public var task: TaskKind
}

public enum ModelRouter {
    /// Geschätzte Token je Sekunde aus Speicherbandbreite und aktiven Parametern.
    public static func estimatedTokensPerSecond(_ spec: ModelSpec, bandwidthGBs: Double) -> Double {
        let bits = spec.bits ?? 4.5
        let bytesPerToken = spec.effectiveActiveB * 1_000_000_000 * bits / 8
        guard bytesPerToken > 0 else { return 10 }
        return max(1, bandwidthGBs * 1_000_000_000 * 0.62 / bytesPerToken)
    }

    public static func quality(_ spec: ModelSpec, for kind: TaskKind) -> Double {
        let w = kind.weights
        let s = spec.skills
        return w.general * s.general + w.coding * s.coding + w.reasoning * s.reasoning + w.writing * s.writing
    }

    static func longContextCaps(_ spec: ModelSpec) -> Set<Capability> {
        spec.contextLength >= 65_536 ? [Capability.longContext] : []
    }

    /// Tempo-Punkte: über ~40 Token/s merkt man kaum noch einen Unterschied.
    static func speedScore(_ tps: Double) -> Double {
        min(10, 10 * log(tps + 1) / log(41))
    }

    public static func route(_ request: RoutingRequest) -> RoutingDecision {
        let profile = request.profile
        let d = max(1, min(5, profile.difficulty))
        var qWeight = [0.5, 0.65, 0.78, 0.87, 0.93][d - 1]
        if profile.kind.isSoftwareStep {
            // Bei Software-Arbeit zählt die Qualität deutlich mehr als das Tempo.
            qWeight = max(qWeight, 0.78)
        } else if profile.prefersSpeed {
            qWeight -= 0.1
        }
        let sWeight = 1 - qWeight

        var scores: [CandidateScore] = []
        for candidate in request.candidates {
            let spec = candidate.spec
            let tps = candidate.measuredTokensPerSecond ?? estimatedTokensPerSecond(spec, bandwidthGBs: request.hardware.memoryBandwidthGBs)
            let q = quality(spec, for: profile.kind)
            let s = speedScore(tps)
            var score = CandidateScore(id: spec.id, name: spec.displayName, quality: q, speed: s, total: 0, tokensPerSecond: tps,
                                       excluded: nil, plan: nil)
            if !candidate.available {
                score.excluded = candidate.unavailableReason ?? "nicht verfügbar"
            } else if let block = spec.license.regionBlock {
                score.excluded = "Lizenz gesperrt: \(block)"
            } else if spec.contextLength < request.neededContextTokens {
                score.excluded = "Kontextfenster zu klein (\(Formatting.context(spec.contextLength)), benötigt \(Formatting.context(request.neededContextTokens)))"
            } else if let missing = profile.required.subtracting(spec.capabilities.union(longContextCaps(spec))).first {
                score.excluded = "kann nicht: \(missing.label)"
            } else {
                // Kontext für den KV-Cache: was der Chat braucht, mindestens 8K
                let plan = MemoryPlanner.plan(for: spec, contextTokens: max(8192, request.neededContextTokens), loaded: request.loaded,
                                              hardware: request.hardware)
                score.plan = plan
                if !plan.fits {
                    score.excluded = "passt nicht in den Speicher (\(plan.reason ?? ""))"
                } else {
                    var total = qWeight * q + sWeight * s
                    if !plan.alreadyLoaded {
                        let loadSeconds = Double(spec.sizeBytes) / max(0.1, request.hardware.diskReadGBs * 1_000_000_000)
                        total -= min(1.2, loadSeconds / 20) * (d <= 2 ? 1.0 : 0.5)
                        total -= 0.2 * Double(plan.unload.count)
                    }
                    score.total = total
                }
            }
            scores.append(score)
        }

        let eligible = scores.filter { $0.excluded == nil }.sorted { $0.total == $1.total ? $0.id < $1.id : $0.total > $1.total }
        func spec(_ id: String?) -> ModelSpec? { request.candidates.first { $0.spec.id == id }?.spec }
        let previous = request.currentModelID

        switch request.mode {
        case .manual:
            guard let pinnedID = request.pinnedModelID, let pinned = spec(pinnedID) else {
                return RoutingDecision(chosen: nil, switched: false, previousModelID: previous,
                                       summary: "Im manuellen Modus ist noch kein Modell gewählt.",
                                       reasons: ["Bitte ein Modell auswählen oder AUTO einschalten."], plan: nil, scores: scores,
                                       suggestion: spec(eligible.first?.id), suggestionReason: eligible.first.map { "Vorschlag für \(profile.kind.label): \($0.name)" },
                                       failure: "Kein Modell gewählt", mode: .manual, task: profile.kind)
            }
            let pinnedScore = scores.first { $0.id == pinnedID }
            if let excluded = pinnedScore?.excluded {
                let alt = eligible.first
                return RoutingDecision(chosen: nil, switched: false, previousModelID: previous,
                                       summary: "\(pinned.displayName) kann diese Anfrage gerade nicht bearbeiten: \(excluded).",
                                       reasons: ["Manueller Modus: Panora ersetzt das gewählte Modell nicht selbstständig."],
                                       plan: pinnedScore?.plan, scores: scores, suggestion: spec(alt?.id),
                                       suggestionReason: alt.map { "Stattdessen \($0.name) verwenden?" },
                                       failure: excluded, mode: .manual, task: profile.kind)
            }
            var reasons = ["Manuell gewählt – gilt für den ganzen Chat."]
            if let p = pinnedScore { reasons.append(contentsOf: detailReasons(p, spec: pinned, profile: profile, request: request)) }
            var suggestion: ModelSpec?
            var suggestionReason: String?
            if request.allowSwitchInManual, let best = eligible.first, best.id != pinnedID,
               let p = pinnedScore, best.total - p.total > 1.0 {
                suggestion = spec(best.id)
                suggestionReason = "Für \(profile.kind.label) wäre \(best.name) besser geeignet. Wechseln?"
            }
            return RoutingDecision(chosen: pinned, switched: previous != nil && previous != pinnedID, previousModelID: previous,
                                   summary: "\(pinned.displayName) arbeitet (manuell gewählt).", reasons: reasons,
                                   plan: pinnedScore?.plan, scores: scores, suggestion: suggestion, suggestionReason: suggestionReason,
                                   failure: nil, mode: .manual, task: profile.kind)

        case .auto:
            guard var best = eligible.first else {
                let why = scores.isEmpty ? "Es ist noch kein lokales Modell installiert." : "Kein installiertes Modell passt gerade (Speicher, Kontext oder Laufwerk)."
                return RoutingDecision(chosen: nil, switched: false, previousModelID: previous, summary: why,
                                       reasons: scores.compactMap { s in s.excluded.map { "\(s.name): \($0)" } },
                                       plan: nil, scores: scores, suggestion: nil, suggestionReason: nil, failure: why,
                                       mode: .auto, task: profile.kind)
            }
            var stayed = false
            if let current = previous, current != best.id, let currentScore = eligible.first(where: { $0.id == current }) {
                // Ein laufendes Modell bleibt, wenn es fast so gut ist – kein unnötiger Wechsel mitten im Gespräch.
                let margin = request.stickiness * (profile.kind.isSoftwareStep ? 0.8 : 1.0)
                if currentScore.total >= best.total - margin {
                    best = currentScore
                    stayed = true
                }
            }
            guard let chosen = spec(best.id) else {
                return RoutingDecision(chosen: nil, switched: false, previousModelID: previous, summary: "Interner Fehler im Router.",
                                       reasons: [], plan: nil, scores: scores, suggestion: nil, suggestionReason: nil,
                                       failure: "Interner Fehler", mode: .auto, task: profile.kind)
            }
            let switched = previous != nil && previous != chosen.id
            var reasons: [String] = []
            let evidence = profile.signals.prefix(2).joined(separator: ", ")
            reasons.append("Aufgabe: \(profile.kind.label)" + (evidence.isEmpty ? "" : " (\(evidence))"))
            reasons.append(contentsOf: detailReasons(best, spec: chosen, profile: profile, request: request))
            if stayed { reasons.append("Bleibt beim aktuellen Modell – ein Wechsel brächte kaum Vorteile.") }
            let runnerUp = eligible.first { $0.id != chosen.id }
            if let r = runnerUp { reasons.append("Nächste Wahl: \(r.name)") }

            let summary: String
            if switched, let prevSpec = spec(previous) {
                summary = "Wechsel von \(prevSpec.displayName) zu \(chosen.displayName): besser geeignet für \(profile.kind.label)."
            } else if switched {
                summary = "Wechsel zu \(chosen.displayName) für \(profile.kind.label)."
            } else if stayed || previous == chosen.id {
                summary = "\(chosen.displayName) arbeitet weiter (\(profile.kind.label))."
            } else {
                summary = "\(chosen.displayName) übernimmt: \(profile.kind.label)."
            }
            return RoutingDecision(chosen: chosen, switched: switched, previousModelID: previous, summary: summary, reasons: reasons,
                                   plan: best.plan, scores: scores, suggestion: nil, suggestionReason: nil, failure: nil,
                                   mode: .auto, task: profile.kind)
        }
    }

    private static func detailReasons(_ score: CandidateScore, spec: ModelSpec, profile: TaskProfile, request: RoutingRequest) -> [String] {
        var reasons: [String] = []
        reasons.append("Erwartete Qualität für \(profile.kind.label): \(Formatting.decimal(score.quality, digits: 1)) von 10")
        reasons.append("Tempo: ca. \(Int(score.tokensPerSecond.rounded())) Token/s")
        if let plan = score.plan {
            reasons.append("Speicher: \(Formatting.bytes(plan.required)) von \(Formatting.bytes(plan.budget)) Budget")
            if plan.alreadyLoaded {
                reasons.append("Bereits geladen – keine Ladezeit")
            } else {
                let seconds = Double(spec.sizeBytes) / max(0.1, request.hardware.diskReadGBs * 1_000_000_000)
                reasons.append("Ladezeit ca. \(Formatting.duration(seconds))")
            }
            if !plan.unload.isEmpty {
                let names = plan.unload.compactMap { id in request.candidates.first { $0.spec.id == id }?.spec.displayName ?? id }
                reasons.append("Entlädt dafür: \(names.joined(separator: ", ")) (am längsten ungenutzt)")
            }
        }
        return reasons
    }
}
