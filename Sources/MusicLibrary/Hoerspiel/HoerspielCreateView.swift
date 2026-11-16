import SwiftUI
import MLCore
import MLStudio

// „Hörbuch erstellen“ / „Hörspiel erstellen“: große Eingabe wie im Gespräch, Länge, eigene Figuren,
// Stilreferenz, Erzählstil bzw. Retro-Klang, Musik/Geräusche – dann läuft die ganze Produktion.

struct HSCreateView: View {
    @ObservedObject var hs: HoerspielModel
    let mode: HSMode
    @Environment(\.musicColors) private var colors
    @State private var newCharacter = ""
    @State private var customMinutes = ""

    static let examples: [(String, String)] = [
        ("Jugendkrimi 1984", "Erstelle ein spannendes deutsches Jugendkrimi-Hörspiel, das im Sommer 1984 spielt. Vier Jugendliche geraten in einen mysteriösen Kriminalfall rund um einen verlassenen Bahnhof. Es gibt mehrere Verdächtige, humorvolle Dialoge, überraschende Wendungen und ein spannendes Finale. Die Produktion soll sich an der Atmosphäre klassischer deutscher Jugendkrimi-Hörspiele der 1980er-Jahre orientieren."),
        ("Detektivgeschichte", "Eine Privatdetektivin in Hamburg, 1950er-Jahre, Regen, Jazz aus der Hafenbar. Ein verschwundener Ring, eine Familie mit Geheimnissen und eine Auflösung, die niemand erwartet."),
        ("Abenteuer", "Drei Geschwister finden auf dem Dachboden eine alte Seekarte und folgen ihr in den Sommerferien bis zu einer Insel in der Ostsee."),
        ("Science-Fiction", "An Bord eines Forschungsschiffs am Rand des Sonnensystems meldet die Bordintelligenz ein Signal, das es nicht geben dürfte."),
        ("Grusel", "Eine Schulklasse übernachtet in einer alten Jugendherberge im Harz. In der Nacht hört man Schritte im leeren Dachgeschoss."),
        ("Psychothriller", "Eine Radiomoderatorin bekommt jede Nacht um 3 Uhr denselben Anruf – und der Anrufer weiß Dinge, die er nicht wissen kann."),
        ("Historischer Fall", "Köln im Jahr 1897: Ein junger Polizeianwärter untersucht einen Diebstahl im Dom, der mehr verbirgt als ein fehlendes Kreuz."),
        ("Fantasy", "Ein Lehrling eines Kartenzeichners entdeckt, dass die Orte auf seinen Karten erst entstehen, wenn er sie zeichnet."),
    ]

    var body: some View {
        let d = Binding(get: { hs.draft(mode) }, set: { hs.drafts[mode] = $0 })
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Stories come alive.")
                    .font(Typo.inter(34, .bold))
                    .tracking(-0.8)
                    .foregroundStyle(LinearGradient(colors: [colors.textPrimary, colors.accentText], startPoint: .leading, endPoint: .trailing))
                Text(mode == .hoerspiel
                     ? "Beschreibe dein Hörspiel – Genre, Zeit, Ort, Figuren, Stimmung. Die KI schreibt eine eigene Geschichte, besetzt die Rollen und produziert sie mit Geräuschen und Musik."
                     : "Beschreibe dein Hörbuch – die KI schreibt eine eigene Geschichte in Kapiteln und eine Erzählerstimme liest sie vor.")
                    .textStyle(Typo.bodyMedium)
                    .foregroundColor(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ZStack(alignment: .topLeading) {
                if d.wrappedValue.prompt.isEmpty {
                    Text("z. B. „Ein Krimi in einem kleinen Dorf an der Nordsee, drei Freundinnen, ein verschwundener Leuchtturmwärter …“")
                        .textStyle(Typo.bodyLarge)
                        .foregroundColor(colors.textTertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: d.prompt)
                    .font(Typo.inter(15, .regular))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 110, maxHeight: 220)
                    .accessibilityLabel("Beschreibung der Geschichte")
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(colors.fieldFill))
            StudioFlow(spacing: 8) {
                ForEach(Self.examples, id: \.0) { e in
                    Button { hs.drafts[mode, default: .init()].prompt = e.1 } label: {
                        Text(e.0)
                            .textStyle(Typo.labelMedium)
                            .foregroundColor(colors.textPrimary)
                            .padding(.horizontal, 11)
                            .frame(height: 28)
                            .glassSurface(Capsule(), interactive: true)
                    }
                    .buttonStyle(PressScaleStyle(scale: 0.96))
                    .help(e.1)
                }
            }
            Hairline()
            length(d)
            characters(d)
            HStack(alignment: .top, spacing: 24) {
                reference(d).frame(maxWidth: .infinity, alignment: .leading)
                if mode == .hoerbuch { narration(d).frame(maxWidth: .infinity, alignment: .leading) }
                else { retro(d).frame(maxWidth: .infinity, alignment: .leading) }
            }
            HStack(spacing: 18) {
                Toggle("Musik (über KI-Musik)", isOn: d.useMusic).toggleStyle(.checkbox)
                if mode == .hoerspiel { Toggle("Geräusche und Atmosphäre", isOn: d.useSFX).toggleStyle(.checkbox) }
                Spacer()
                Text("Sprache").foregroundColor(colors.textSecondary)
                Picker("", selection: d.language) {
                    ForEach(HSVoiceDesign.languages, id: \.code) { l in Text(l.name).tag(l.code) }
                }
                .labelsHidden()
                .frame(width: 130)
                .help("Sprache der Geschichte und der Stimmen. Deutsch ist am gründlichsten geprüft (Zahlen, Abkürzungen, Aussprache).")
            }
            .font(Typo.inter(13, .medium))
            HStack(spacing: 12) {
                PillButton(title: mode == .hoerspiel ? "Hörspiel produzieren" : "Hörbuch produzieren", icon: Icons.autoAwesome,
                           style: .filled, minWidth: 200) { hs.create(mode) }
                    .disabled(blocker(d.wrappedValue) != nil || hs.isWorking)
                    .keyboardShortcut(.return, modifiers: .command)
                Text(blocker(d.wrappedValue) ?? hint(d.wrappedValue))
                    .textStyle(Typo.bodySmall)
                    .foregroundColor(blocker(d.wrappedValue) == nil ? colors.textSecondary : colors.danger)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous), strong: true)
    }

    private func blocker(_ d: HoerspielModel.Draft) -> String? {
        if d.prompt.trimmingCharacters(in: .whitespacesAndNewlines).count < 12 { return "Beschreibe die Geschichte in ein, zwei Sätzen." }
        if hs.setup != .ready { return "Zuerst KI-Hörbücher einrichten." }
        return nil
    }

    private func hint(_ d: HoerspielModel.Draft) -> String {
        let plan = HSPlan.size(minutes: d.minutes)
        return "Ziel: ca. \(Int(d.minutes)) min · \(plan.chapters) Kapitel mit je ca. \(plan.scenesPerChapter) Szenen · ca. "
            + "\(HSPlan.targetWords(minutes: d.minutes)) gesprochene Wörter. Die tatsächliche Länge ergibt sich aus dem geschriebenen Text. "
            + "Eine Stunde Hörspiel kann mehrere Stunden Rechenzeit brauchen."
    }

    private func length(_ d: Binding<HoerspielModel.Draft>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HSFormat.label("Länge", colors)
            StudioFlow(spacing: 6) {
                ForEach(HSPlan.presets, id: \.self) { m in
                    let on = d.wrappedValue.minutes == m
                    Button { d.wrappedValue.minutes = m } label: {
                        Text("\(Int(m)) min")
                            .font(Typo.inter(12, on ? .semibold : .medium))
                            .foregroundColor(on ? colors.accentText : colors.textPrimary)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(Capsule().fill(on ? colors.accentSoft : colors.textPrimary.opacity(0.05)))
                    }
                    .buttonStyle(.plain)
                }
                HStack(spacing: 4) {
                    TextField("eigene", text: $customMinutes)
                        .textFieldStyle(.plain)
                        .font(Typo.inter(12, .medium))
                        .frame(width: 50)
                        .onSubmit {
                            if let v = Double(customMinutes.replacingOccurrences(of: ",", with: ".")), v >= 2, v <= 180 { d.wrappedValue.minutes = v.rounded() }
                        }
                    Text("min").font(Typo.inter(12, .medium)).foregroundColor(colors.textSecondary)
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Capsule().fill(colors.textPrimary.opacity(0.05)))
                .help("Eigene Länge in Minuten (2 bis 180), mit Eingabetaste übernehmen")
            }
        }
    }

    private func characters(_ d: Binding<HoerspielModel.Draft>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HSFormat.label("Eigene Figuren (optional)", colors)
            StudioFlow(spacing: 6) {
                ForEach(Array(d.wrappedValue.characters.enumerated()), id: \.offset) { i, c in
                    HStack(spacing: 4) {
                        Text(c).font(Typo.inter(12, .medium)).foregroundColor(colors.textPrimary).lineLimit(1)
                        Button { d.wrappedValue.characters.remove(at: i) } label: { Icon(Icons.close, size: 12, color: colors.textSecondary) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Figur entfernen")
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Capsule().fill(colors.accentSoft))
                }
                TextField("z. B. „Paula, 14, mutig, Fotografin“ – Eingabetaste", text: $newCharacter)
                    .textFieldStyle(.plain)
                    .font(Typo.inter(12.5, .regular))
                    .frame(minWidth: 260)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Capsule().fill(colors.fieldFill))
                    .onSubmit {
                        let t = newCharacter.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !t.isEmpty { d.wrappedValue.characters.append(t) }
                        newCharacter = ""
                    }
            }
            Text("Namen, Schauplätze und Handlungsstränge darfst du frei vorgeben – die KI übernimmt sie in ihr Konzept.")
                .textStyle(Typo.bodySmall).foregroundColor(colors.textTertiary)
        }
    }

    private func reference(_ d: Binding<HoerspielModel.Draft>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HSFormat.label("Stilreferenz", colors)
            Picker("", selection: d.referenceID) {
                Text("Keine").tag(UUID?.none)
                ForEach(hs.references) { r in Text(r.name).tag(UUID?.some(r.id)) }
            }
            .labelsHidden()
            .frame(maxWidth: 320)
            Text(hs.references.isEmpty ? "Unter „Referenz analysieren“ kannst du eigene Aufnahmen auswerten – übernommen werden nur allgemeine Merkmale wie Tempo, Erzählweise und Klang."
                 : "Nur allgemeine Merkmale (Dialogtempo, Erzählanteil, Klang) – keine Handlung, keine Namen, keine Stimmen.")
                .textStyle(Typo.bodySmall).foregroundColor(colors.textTertiary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func retro(_ d: Binding<HoerspielModel.Draft>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HSFormat.label("Klang der 1980er", colors)
            HStack(spacing: 10) {
                Slider(value: d.retro, in: 0...1)
                    .frame(maxWidth: 220)
                Text(d.wrappedValue.retro < 0.05 ? "aus" : "\(Int((d.wrappedValue.retro * 100).rounded())) %")
                    .font(Typo.inter(12, .medium)).monospacedDigit().foregroundColor(colors.textSecondary)
            }
            Text("Bandbreite, leichte Bandsättigung, minimales Rauschen und Gleichlauf wie bei einer Hörspielkassette – allgemeine Merkmale, keine Kopie einer Aufnahme.")
                .textStyle(Typo.bodySmall).foregroundColor(colors.textTertiary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func narration(_ d: Binding<HoerspielModel.Draft>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HSFormat.label("Erzählstil", colors)
            StudioFlow(spacing: 6) {
                ForEach(["klassisch", "spannend", "humorvoll", "märchenhaft", "sachlich"], id: \.self) { s in
                    ChoiceChip(title: s.capitalized, selected: d.wrappedValue.narration == s) { d.wrappedValue.narration = s }
                }
            }
        }
    }
}
