import SwiftUI
import AppKit
import MLCore
import MLStudio

// Geschichten-Editor: Kapitel und Szenen ansehen und bearbeiten, Dialoge ändern, Figuren hinzufügen/entfernen,
// Szenen oder einzelne Repliken neu schreiben, Alternativen und frühere Fassungen, eigene Aussprache.
// Änderungen an einer Szene markieren nur die abhängigen Schritte als veraltet – der Rest bleibt unberührt.

struct HSEditorView: View {
    @ObservedObject var hs: HoerspielModel
    @Environment(\.musicColors) private var colors
    @State private var sceneIndex = 0

    var body: some View {
        if let p = hs.current {
            VStack(alignment: .leading, spacing: 14) {
                header(p)
                SegmentedControl(options: HoerspielModel.EditorTab.allCases, selection: $hs.editorTab, label: { t in
                    switch t {
                    case .script: return "Kapitel & Szenen"
                    case .figures: return "Figuren & Stimmen"
                    case .pronunciation: return "Aussprache"
                    case .multitrack: return "Mehrspur"
                    }
                })
                .frame(maxWidth: 640)
                switch hs.editorTab {
                case .script:
                    if p.scenes.isEmpty {
                        StudioNotice(icon: Icons.info, title: "Noch kein Drehbuch", text: "Die Geschichte wird gerade geschrieben oder wurde noch nicht begonnen.") {
                            PillButton(title: "Geschichte schreiben", style: .filled) { hs.runStep(.story, p.id) }.disabled(hs.isWorking)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            reviewCard(p)
                            HStack(alignment: .top, spacing: 16) {
                                sceneList(p).frame(width: 270)
                                HSSceneEditor(hs: hs, productionID: p.id, index: min(sceneIndex, p.scenes.count - 1))
                            }
                        }
                    }
                case .figures: HSFiguresEditor(hs: hs, productionID: p.id)
                case .pronunciation: HSPronunciationEditor(hs: hs, productionID: p.id)
                case .multitrack: HSMultitrackView(hs: hs, productionID: p.id)
                }
            }
        } else {
            EmptyStateView(icon: Icons.editNote, title: "Keine Produktion ausgewählt",
                           text: "Erstelle zuerst ein Hörbuch oder Hörspiel – dann kannst du hier Kapitel, Szenen und Dialoge bearbeiten.")
        }
    }

    private func header(_ p: HSProduction) -> some View {
        HStack(alignment: .center, spacing: 12) {
            GlassMenuButton(help: "Produktion wählen", width: 340) {
                HStack(spacing: 6) {
                    Text(p.title.isEmpty ? "Neue Produktion" : p.title).textStyle(Typo.titleLarge).foregroundColor(colors.textPrimary).lineLimit(1)
                    Icon(Icons.unfoldMore, size: 14, color: colors.textTertiary)
                }
            } content: { menu in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(hs.productions) { q in
                            GlassMenuItem(title: q.title.isEmpty ? "Neue Produktion" : q.title, checked: q.id == p.id) {
                                hs.currentID = q.id
                                sceneIndex = 0
                                menu.close()
                            }
                        }
                    }
                }
                .frame(maxHeight: 360)
            }
            Spacer()
            HSStepsRow(production: p)
        }
    }

    private func sceneList(_ p: HSProduction) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(p.chapters, id: \.number) { ch in
                Text("Kapitel \(ch.number)" + (ch.title.isEmpty ? "" : " · \(ch.title)"))
                    .font(Typo.inter(11, .semibold)).foregroundColor(colors.textTertiary)
                    .padding(.top, 8).padding(.horizontal, 8)
                ForEach(Array(p.scenes.enumerated()).filter { $0.element.chapter == ch.number }, id: \.element.id) { i, s in
                    let on = i == sceneIndex
                    Button { sceneIndex = i } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(s.number). \(s.title)").font(Typo.inter(12.5, on ? .semibold : .medium))
                                .foregroundColor(on ? colors.accentText : colors.textPrimary).lineLimit(1)
                            Text(sceneInfo(s, p)).font(Typo.inter(10.5, .regular)).foregroundColor(colors.textTertiary).lineLimit(1)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? colors.accentSoft : Color.clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(8)
        .glassSurface(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    /// Ergebnis des Lektorats: offene Hinweise mit Sprung zur Szene; erneut ausführen nach eigenen Änderungen.
    @ViewBuilder private func reviewCard(_ p: HSProduction) -> some View {
        let written = p.scenes.count > 1 && p.scenes.allSatisfy { !$0.items.isEmpty }
        if written {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Icon(Icons.info, size: 15, color: colors.textSecondary)
                    if let r = p.review {
                        Text("Lektorat: " + (r.problems.isEmpty ? "keine Widersprüche gefunden"
                                             : "\(r.problems.count) Hinweis\(r.problems.count == 1 ? "" : "e") · "
                                               + (r.revised.isEmpty ? "keine Szene überarbeitet"
                                                  : "Szene \(r.revised.map(String.init).joined(separator: ", ")) überarbeitet")))
                            .textStyle(Typo.bodySmall).foregroundColor(colors.textPrimary)
                    } else {
                        Text("Noch nicht lektoriert – das Sprachmodell prüft die ganze Geschichte auf Widersprüche und Logiklücken.")
                            .textStyle(Typo.bodySmall).foregroundColor(colors.textSecondary)
                    }
                    Spacer()
                    PillButton(title: p.review == nil ? "Lektorat ausführen" : "Erneut prüfen", style: .plain) { hs.reviewAgain(p.id) }
                        .disabled(hs.isWorking || hs.setup != .ready)
                        .help("Prüft die aktuelle Fassung; überarbeitete Szenen behalten ihre vorige Fassung unter „Fassungen“.")
                }
                if let r = p.review {
                    ForEach(Array(r.problems.enumerated()), id: \.offset) { _, prob in
                        Button { sceneIndex = prob.scene - 1 } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("Szene \(prob.scene)").font(Typo.inter(11, .semibold)).foregroundColor(colors.accentText)
                                Text(prob.problem + (prob.fix.isEmpty ? "" : " → " + prob.fix))
                                    .font(Typo.inter(11.5, .regular)).foregroundColor(colors.textSecondary)
                                    .strikethrough(r.revised.contains(prob.scene), color: colors.textTertiary)
                                    .lineLimit(2).multilineTextAlignment(.leading)
                            }
                        }
                        .buttonStyle(.plain)
                        .help(r.revised.contains(prob.scene) ? "In der Überarbeitung behoben – zur Szene springen" : "Offen – zur Szene springen")
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .glassSurface(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
    }

    private func sceneInfo(_ s: HSScene, _ p: HSProduction) -> String {
        let lines = s.items.filter { $0.kind == .line }
        let voiced = lines.filter { $0.audioFile != nil && $0.audioFingerprint == p.fingerprint(of: $0) }.count
        if s.items.isEmpty { return "noch nicht geschrieben" }
        return "\(s.spokenWords) Wörter · \(voiced)/\(lines.count) gesprochen" + (s.versions.isEmpty ? "" : " · \(s.versions.count) Fassungen")
    }
}

// MARK: - Szene

private struct HSSceneEditor: View {
    @ObservedObject var hs: HoerspielModel
    let productionID: UUID
    let index: Int
    @Environment(\.musicColors) private var colors
    @State private var rewriteHint = ""

    var body: some View {
        if let p = hs.production(productionID), p.scenes.indices.contains(index) {
            let s = p.scenes[index]
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    TextField("Titel", text: binding(\.title)).textFieldStyle(.plain).font(Typo.inter(17, .semibold))
                    Picker("", selection: binding(\.room)) {
                        ForEach(HSRoom.all, id: \.id) { r in Text(r.name).tag(r.id) }
                    }
                    .labelsHidden().frame(width: 170).help("Raumklang der Szene")
                }
                VStack(alignment: .leading, spacing: 4) {
                    HSFormat.label("Handlung dieser Szene", colors)
                    TextEditor(text: binding(\.outline))
                        .font(Typo.inter(13, .regular)).scrollContentBackground(.hidden)
                        .frame(minHeight: 50, maxHeight: 90).padding(6)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(colors.fieldFill))
                    Text("Ändere die Handlung und lass die Szene neu schreiben – die übrigen Szenen bleiben unverändert.")
                        .textStyle(Typo.bodySmall).foregroundColor(colors.textTertiary)
                }
                HStack(spacing: 8) {
                    PillButton(title: s.items.isEmpty ? "Szene schreiben" : "Neu schreiben / Alternative", icon: Icons.autoAwesome, style: .tonal) {
                        hs.rewriteScene(productionID, index: index)
                    }
                    .disabled(hs.isWorking || hs.setup != .ready)
                    if !s.versions.isEmpty {
                        GlassMenuButton(help: "Frühere Fassungen", width: 320) {
                            HStack(spacing: 5) {
                                Icon(Icons.history, size: 14, color: colors.textSecondary)
                                Text("Fassungen (\(s.versions.count))").textStyle(Typo.labelMedium).foregroundColor(colors.textSecondary)
                            }
                            .padding(.horizontal, 11).frame(height: 30).glassSurface(Capsule(), interactive: true)
                        } content: { menu in
                            ForEach(Array(s.versions.enumerated()).reversed(), id: \.offset) { i, v in
                                GlassMenuItem(title: "\(v.date.formatted(date: .abbreviated, time: .shortened)) – \(v.note) – wiederherstellen") {
                                    hs.update(productionID) { pr in
                                        pr.scenes[index].restore(versionAt: i)
                                        pr.markChanged(scene: pr.scenes[index].id)
                                    }
                                    menu.close()
                                }
                            }
                        }
                    }
                    Spacer()
                    PillButton(title: "Stimmen dieser Produktion erzeugen", icon: Icons.voice, style: .plain) { hs.runStep(.voices, productionID) }
                        .disabled(hs.isWorking || hs.setup != .ready)
                }
                Hairline()
                ForEach(Array(s.items.enumerated()), id: \.element.id) { ii, item in
                    HSItemRow(hs: hs, production: p, scene: index, item: ii)
                }
                StudioFlow(spacing: 6) {
                    addButton("Zeile", .line)
                    if p.mode == .hoerspiel {
                        addButton("Geräusch", .sfx)
                        addButton("Atmo", .atmo)
                        addButton("Musik", .music)
                    }
                    addButton("Pause", .pause)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
    }

    private func addButton(_ title: String, _ kind: HSScriptItem.Kind) -> some View {
        PillButton(title: "+ \(title)", style: .plain) {
            hs.update(productionID) { p in
                let item: HSScriptItem
                switch kind {
                case .line: item = HSScriptItem(kind: .line, speaker: HSFigure.narratorID, text: "")
                case .pause: item = HSScriptItem(kind: .pause, text: "", seconds: 1.5)
                default: item = HSScriptItem(kind: kind, text: "", english: "")
                }
                p.scenes[index].items.append(item)
                p.markChanged(scene: p.scenes[index].id)
            }
        }
    }

    private func binding<T>(_ kp: WritableKeyPath<HSScene, T>) -> Binding<T> {
        Binding(get: { hs.production(productionID)!.scenes[index][keyPath: kp] },
                set: { v in hs.update(productionID) { $0.scenes[index][keyPath: kp] = v; $0.markChanged(scene: $0.scenes[index].id) } })
    }
}

private struct HSItemRow: View {
    @ObservedObject var hs: HoerspielModel
    let production: HSProduction
    let scene: Int
    let item: Int
    @Environment(\.musicColors) private var colors
    @State private var text = ""
    @State private var english = ""

    var body: some View {
        let it = production.scenes[scene].items[item]
        HStack(alignment: .top, spacing: 8) {
            switch it.kind {
            case .line:
                Picker("", selection: Binding(get: { it.speaker ?? HSFigure.narratorID }, set: { v in edit { $0.speaker = v } })) {
                    ForEach(production.figures) { f in Text(f.name.isEmpty ? f.id : f.name).tag(f.id) }
                }
                .labelsHidden().frame(width: 130)
                VStack(alignment: .leading, spacing: 3) {
                    TextField("Tonfall (z. B. flüsternd)", text: Binding(get: { it.emotion ?? "" }, set: { v in edit { $0.emotion = v.isEmpty ? nil : v } }))
                        .textFieldStyle(.plain).font(Typo.inter(11, .medium)).foregroundColor(colors.textTertiary)
                    TextField("Text", text: $text, axis: .vertical)
                        .textFieldStyle(.plain).font(Typo.inter(13.5, .regular))
                        .onSubmit { commitText() }
                }
                Spacer(minLength: 4)
                if let f = it.audioFile {
                    let current = it.audioFingerprint == production.fingerprint(of: it)
                    GlassIconButton(icon: hs.playingKey == it.id.uuidString ? Icons.pause : Icons.play,
                                    label: current ? "Anhören" : "Anhören (veraltet – Text oder Stimme geändert)", size: 28, iconSize: 14,
                                    tint: current ? nil : Color(argb: 0xFFFF9F0A)) {
                        hs.play(hs.file(f, in: production), key: it.id.uuidString)
                    }
                }
                GlassMenuButton(help: "Zeile", width: 260) {
                    Icon(Icons.moreHoriz, size: 16, color: colors.textSecondary).frame(width: 28, height: 28)
                } content: { menu in
                    GlassMenuItem(title: "Neu sprechen", icon: Icons.voice) { hs.regenerateLine(production.id, scene: scene, item: item); menu.close() }
                    GlassMenuItem(title: "Neu formulieren", icon: Icons.autoAwesome) { hs.rewriteLine(production.id, scene: scene, item: item, hint: ""); menu.close() }
                    GlassMenuItem(title: "Spannender formulieren", icon: Icons.autoAwesome) { hs.rewriteLine(production.id, scene: scene, item: item, hint: "spannender und lebendiger"); menu.close() }
                    GlassMenuItem(title: "Lustiger formulieren", icon: Icons.autoAwesome) { hs.rewriteLine(production.id, scene: scene, item: item, hint: "mit mehr Humor"); menu.close() }
                    GlassMenuDivider()
                    moveItems(menu)
                }
            case .sfx, .atmo, .music:
                Text(it.kind == .sfx ? "GERÄUSCH" : it.kind == .atmo ? "ATMO" : "MUSIK")
                    .font(Typo.inter(10.5, .semibold)).foregroundColor(colors.accentText).frame(width: 130, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    TextField("Beschreibung", text: $text).textFieldStyle(.plain).font(Typo.inter(13, .medium)).onSubmit { commitText() }
                    TextField("englisch fürs Modell", text: $english).textFieldStyle(.plain).font(Typo.inter(11, .regular))
                        .foregroundColor(colors.textTertiary).onSubmit { edit { $0.english = english } }
                }
                Spacer()
                GlassMenuButton(help: "Hinweis", width: 220) {
                    Icon(Icons.moreHoriz, size: 16, color: colors.textSecondary).frame(width: 28, height: 28)
                } content: { menu in moveItems(menu) }
            case .pause:
                Text("PAUSE").font(Typo.inter(10.5, .semibold)).foregroundColor(colors.textTertiary).frame(width: 130, alignment: .leading)
                Stepper(value: Binding(get: { it.seconds ?? 1.5 }, set: { v in edit { $0.seconds = v } }), in: 0.5...6, step: 0.5) {
                    Text(String(format: "%.1f s", it.seconds ?? 1.5)).font(Typo.inter(12, .medium)).monospacedDigit()
                }
                .fixedSize()
                Spacer()
                GlassMenuButton(help: "Pause", width: 220) {
                    Icon(Icons.moreHoriz, size: 16, color: colors.textSecondary).frame(width: 28, height: 28)
                } content: { menu in moveItems(menu) }
            }
        }
        .padding(.vertical, 4)
        .onAppear { text = it.text; english = it.english ?? "" }
        .onChange(of: it.text) { text = $0 }
    }

    @ViewBuilder private func moveItems(_ menu: GlassMenuContext) -> some View {
        GlassMenuItem(title: "Nach oben", icon: Icons.arrowUp) { move(-1); menu.close() }
        GlassMenuItem(title: "Nach unten", icon: Icons.arrowDown) { move(1); menu.close() }
        GlassMenuItem(title: "Entfernen", icon: Icons.delete) {
            hs.update(production.id) { p in
                p.scenes[scene].items.remove(at: item)
                p.markChanged(scene: p.scenes[scene].id)
            }
            menu.close()
        }
    }

    private func move(_ d: Int) {
        let target = item + d
        hs.update(production.id) { p in
            guard p.scenes[scene].items.indices.contains(target) else { return }
            p.scenes[scene].items.swapAt(item, target)
            p.markChanged(scene: p.scenes[scene].id)
        }
    }

    private func commitText() {
        let t = text
        edit { $0.text = t }
    }

    private func edit(_ change: @escaping (inout HSScriptItem) -> Void) {
        hs.update(production.id) { p in
            guard p.scenes.indices.contains(scene), p.scenes[scene].items.indices.contains(item) else { return }
            change(&p.scenes[scene].items[item])
            p.markChanged(scene: p.scenes[scene].id)
        }
    }
}

// MARK: - Figuren

private struct HSFiguresEditor: View {
    @ObservedObject var hs: HoerspielModel
    let productionID: UUID
    @Environment(\.musicColors) private var colors
    @State private var newName = ""
    @State private var newDescription = ""
    @State private var newVoice = ""

    var body: some View {
        if let p = hs.production(productionID) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(p.figures) { f in figureRow(f, p) }
                Hairline()
                HSFormat.label("Figur hinzufügen", colors)
                HStack {
                    TextField("Name", text: $newName).frame(width: 140)
                    TextField("Beschreibung (Rolle, Charakter)", text: $newDescription)
                    TextField("Stimme (englisch für das Modell, z. B. „A gruff man in his sixties“)", text: $newVoice)
                    PillButton(title: "Hinzufügen", style: .tonal) {
                        let n = newName.trimmingCharacters(in: .whitespaces)
                        guard !n.isEmpty else { return }
                        hs.update(productionID) {
                            $0.figures.append(HSFigure(id: n, name: n, role: "Nebenfigur", description: newDescription, voiceEN: newVoice))
                        }
                        newName = ""; newDescription = ""; newVoice = ""
                    }
                }
                .textFieldStyle(.roundedBorder)
                Text("Neue Figuren kommen in Szenen vor, die du neu schreiben lässt oder in die du selbst Zeilen einfügst.")
                    .textStyle(Typo.bodySmall).foregroundColor(colors.textTertiary)
            }
            .padding(16)
            .glassSurface(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
    }

    private func figureRow(_ f: HSFigure, _ p: HSProduction) -> some View {
        let lines = p.scenes.reduce(0) { $0 + $1.items.filter { $0.speaker == f.id }.count }
        let cast = p.cast[f.id]
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(f.name.isEmpty ? f.id : f.name).textStyle(Typo.titleSmall).foregroundColor(colors.textPrimary)
                    Text(f.role).textStyle(Typo.bodySmall).foregroundColor(colors.textTertiary)
                    if f.addedByModel { Text("vom Modell ergänzt").font(Typo.inter(10, .medium)).foregroundColor(Color(argb: 0xFFFF9F0A)) }
                }
                Text(f.description).textStyle(Typo.bodySmall).foregroundColor(colors.textSecondary).lineLimit(2)
                Text("Stimme: " + (f.voice.isEmpty ? f.voiceEN : f.voice)).textStyle(Typo.bodySmall).foregroundColor(colors.textTertiary).lineLimit(2)
                Text("\(lines) Zeilen" + (cast.map { " · " + ($0.kind == .designed ? "entworfene Stimme" : $0.kind == .authorized ? "berechtigte Stimme" : "") } ?? " · noch keine Stimme"))
                    .font(Typo.inter(10.5, .medium)).foregroundColor(colors.textTertiary)
            }
            Spacer()
            if let c = cast {
                GlassIconButton(icon: hs.playingKey == "cast-\(f.id)" ? Icons.pause : Icons.play, label: "Stimme anhören", size: 30, iconSize: 15) {
                    hs.play(hs.file(c.referenceFile, in: p), key: "cast-\(f.id)")
                }
            }
            Picker("", selection: Binding(get: { f.voiceProfileID }, set: { hs.recast(productionID, figure: f.id, profile: $0) })) {
                Text("Aus Beschreibung entwerfen").tag(UUID?.none)
                ForEach(hs.voices.filter(\.canSpeak)) { v in Text("\(v.name) (\(v.kind.label))").tag(UUID?.some(v.id)) }
            }
            .labelsHidden().frame(width: 230).help("Stimme aus dem Stimmenstudio zuweisen")
            GlassMenuButton(help: "Figur", width: 260) {
                Icon(Icons.moreHoriz, size: 16, color: colors.textSecondary).frame(width: 28, height: 28)
            } content: { menu in
                GlassMenuItem(title: "Stimme neu entwerfen", icon: Icons.refresh) {
                    hs.recast(productionID, figure: f.id, profile: f.voiceProfileID)
                    menu.close()
                }
                GlassMenuItem(title: lines == 0 ? "Figur entfernen" : "Entfernen (erst Zeilen umbesetzen)", icon: Icons.delete) {
                    if lines == 0 { hs.update(productionID) { $0.figures.removeAll { $0.id == f.id }; $0.cast[f.id] = nil } }
                    menu.close()
                }
            }
        }
    }
}

// MARK: - Aussprache

private struct HSPronunciationEditor: View {
    @ObservedObject var hs: HoerspielModel
    let productionID: UUID
    @Environment(\.musicColors) private var colors
    @State private var written = ""
    @State private var spoken = ""

    var body: some View {
        if let p = hs.production(productionID) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Eigene Aussprache: Namen, Abkürzungen oder Fremdwörter so schreiben, wie sie gesprochen werden sollen. Gilt für alle Zeilen dieser Produktion; betroffene Zeilen werden beim nächsten „Stimmen erzeugen“ neu gesprochen.")
                    .textStyle(Typo.bodySmall).foregroundColor(colors.textSecondary).fixedSize(horizontal: false, vertical: true)
                ForEach(p.pronunciations.keys.sorted(), id: \.self) { k in
                    HStack {
                        Text(k).font(Typo.inter(13, .semibold)).frame(width: 200, alignment: .leading)
                        Text("→ " + (p.pronunciations[k] ?? "")).font(Typo.inter(13, .regular))
                        Spacer()
                        Button { hs.update(productionID) { $0.pronunciations[k] = nil } } label: { Icon(Icons.delete, size: 15, color: colors.textSecondary) }
                            .buttonStyle(.plain)
                    }
                }
                HStack {
                    TextField("Geschrieben (z. B. „Hjalmar“)", text: $written).frame(width: 220)
                    TextField("Gesprochen (z. B. „Jalmar“)", text: $spoken)
                    PillButton(title: "Hinzufügen", style: .tonal) {
                        let w = written.trimmingCharacters(in: .whitespaces), s = spoken.trimmingCharacters(in: .whitespaces)
                        guard !w.isEmpty, !s.isEmpty else { return }
                        hs.update(productionID) { $0.pronunciations[w] = s }
                        written = ""; spoken = ""
                    }
                }
                .textFieldStyle(.roundedBorder)
            }
            .padding(16)
            .glassSurface(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
    }
}
