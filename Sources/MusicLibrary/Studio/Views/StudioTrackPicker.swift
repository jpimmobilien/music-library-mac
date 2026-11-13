import SwiftUI
import AppKit
import MLCore
import MLStudio

// Studio (2.4) ohne geladenen Titel: was das Studio kann und eine Auswahl aus der Bibliothek – der gerade
// laufende Titel, zuletzt hinzugefügte und die Suche. Ein Klick öffnet den Titel zum Bearbeiten,
// „Schneiden“ öffnet ihn nur zum Schneiden (verlustfrei, wenn möglich).

struct StudioTrackPicker: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerService
    @ObservedObject var studio: StudioModel
    @Environment(\.musicColors) private var colors
    let width: CGFloat
    @State private var query = ""
    @State private var recent: [Track] = []

    /// Höchstens so viele Zeilen (Suche bzw. „Zuletzt hinzugefügt“) – große Bibliotheken bleiben flüssig.
    static let searchLimit = 80
    static let recentLimit = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StudioToolOverview(columns: width >= 900 ? 3 : (width >= 560 ? 2 : 1))
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Titel wählen")
                        .textStyle(Typo.titleLarge)
                        .foregroundColor(colors.textPrimary)
                    Text("Klick öffnet den Titel zum Bearbeiten")
                        .textStyle(Typo.bodySmall)
                        .foregroundColor(colors.textTertiary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                SearchField(text: $query, placeholder: "Titel, Interpret oder Album suchen")
                if let current = player.current, query.isEmpty, let track = model.track(current.uid) {
                    section("Läuft gerade")
                    StudioPickerRow(studio: studio, track: track, highlight: true)
                }
                let shown = rows
                section(query.isEmpty ? "Zuletzt hinzugefügt" : resultLabel(shown.count))
                if shown.isEmpty {
                    StudioPanelEmpty(icon: query.isEmpty ? Icons.libraryMusic : Icons.search,
                                     title: query.isEmpty ? "Noch keine Titel" : "Keine Treffer",
                                     text: query.isEmpty ? "Füge zuerst Musik hinzu – über „Hinzufügen“ oder einen Musikordner in den Einstellungen."
                                                         : "Kein Titel passt zu „\(query)“.")
                } else {
                    LazyVStack(spacing: 2) {
                        ForEach(shown, id: \.uid) { t in StudioPickerRow(studio: studio, track: t, highlight: false) }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(RoundedRectangle(cornerRadius: Radius.card + 4, style: .continuous))
        }
        .task(id: recentSignature) { recent = Self.recentTracks(model.index.tracks) }
    }

    private var rows: [Track] {
        if query.trimmingCharacters(in: .whitespaces).isEmpty { return recent }
        return Array(model.index.searchTracks(query).prefix(Self.searchLimit))
    }

    /// Neu berechnen, wenn sich die Bibliothek ändert (Anzahl oder jüngster Titel).
    private var recentSignature: String {
        let tracks = model.index.tracks
        return "\(tracks.count)-\(tracks.last?.uid ?? 0)-\(tracks.first?.uid ?? 0)"
    }

    private func resultLabel(_ count: Int) -> String {
        count >= Self.searchLimit ? "Die ersten \(count) Treffer" : (count == 1 ? "1 Treffer" : "\(count) Treffer")
    }

    private func section(_ title: String) -> some View {
        Text(title.uppercased())
            .font(Typo.inter(10.5, .semibold))
            .tracking(0.6)
            .foregroundColor(colors.textTertiary)
            .padding(.horizontal, 4)
            .padding(.top, 2)
    }

    /// Zuletzt hinzugefügte Titel (neueste zuerst).
    nonisolated static func recentTracks(_ tracks: [Track]) -> [Track] {
        var best: [Track] = []
        best.reserveCapacity(recentLimit + 1)
        for t in tracks {
            if best.count < recentLimit || t.dateAdded > best[best.count - 1].dateAdded {
                let i = best.firstIndex(where: { t.dateAdded > $0.dateAdded }) ?? best.count
                best.insert(t, at: i)
                if best.count > recentLimit { best.removeLast() }
            }
        }
        return best
    }
}

/// Eine Zeile der Auswahl: Cover, Titel, Interpret · Album, Format und Dauer; rechts „Schneiden“ und „Bearbeiten“.
private struct StudioPickerRow: View {
    @ObservedObject var studio: StudioModel
    @Environment(\.musicColors) private var colors
    let track: Track
    let highlight: Bool
    @State private var hover = false

    var body: some View {
        HStack(spacing: 12) {
            TrackArtwork(track: track, size: .small, cornerRadius: Radius.artworkSmall)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(track.displayTitle)
                    .textStyle(Typo.bodyMedium)
                    .fontWeight(.medium)
                    .foregroundColor(track.available ? colors.textPrimary : colors.textTertiary)
                    .lineLimit(1)
                Text(subtitle)
                    .textStyle(Typo.bodySmall)
                    .foregroundColor(colors.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if !track.available {
                Text("nicht verfügbar")
                    .textStyle(Typo.labelSmall)
                    .foregroundColor(colors.textTertiary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(colors.fieldFill))
            } else if hover || highlight {
                Button { studio.openLibraryTrack(track.uid) } label: {
                    HStack(spacing: 5) {
                        Icon(Icons.cut, size: 14, color: colors.textSecondary)
                        Text("Schneiden").textStyle(Typo.labelMedium).foregroundColor(colors.textSecondary)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Capsule().fill(colors.textPrimary.opacity(0.06)))
                    .contentShape(Capsule())
                }
                .buttonStyle(PressScaleStyle(scale: 0.96))
                .help("Nur schneiden – als neue Datei oder anstelle des Originals")
                HStack(spacing: 5) {
                    Icon(Icons.tune, size: 14, color: colors.accentText)
                    Text("Bearbeiten").textStyle(Typo.labelMedium).foregroundColor(colors.accentText)
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Capsule().fill(colors.accentSoft))
            }
            Text(meta)
                .textStyle(Typo.labelMedium)
                .monospacedDigit()
                .foregroundColor(colors.textTertiary)
                .lineLimit(1)
                .frame(minWidth: 86, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .frame(height: 54)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(highlight ? colors.accentSoft.opacity(0.5) : (hover ? colors.textPrimary.opacity(0.05) : .clear)))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture { if track.available { studio.openTrackEditor(track.uid) } }
        .onHover { hover = $0 }
        .animation(Motion.easeOut(Motion.short), value: hover)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(track.displayTitle), \(subtitle)")
        .accessibilityHint("Öffnet den Titel zum Bearbeiten")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Bearbeiten") { studio.openTrackEditor(track.uid) }
        .accessibilityAction(named: "Schneiden") { studio.openLibraryTrack(track.uid) }
    }

    private var subtitle: String {
        var parts = [track.artistText ?? "Unbekannter Interpret"]
        if let album = track.album, !album.isEmpty { parts.append(album) }
        return parts.joined(separator: " · ")
    }

    private var meta: String {
        let ext = (track.path as NSString).pathExtension.uppercased()
        let time = track.durationMs > 0 ? Formatting.duration(track.durationMs) : ""
        return [ext, time].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// Was das Studio kann – kurze Kacheln über der Titelauswahl.
private struct StudioToolOverview: View {
    @Environment(\.musicColors) private var colors
    let columns: Int

    private static let tools: [(icon: String, title: String, text: String)] = [
        (Icons.cut, "Beschneiden", "Start und Ende auf die Millisekunde, Ein- und Ausblenden – verlustfrei, wo es geht."),
        (Icons.volumeUp, "Lautstärke & Verbesserung", "Lautheit angleichen, Rumpeln und Stille entfernen, Übersteuerung verhindern."),
        (Icons.speed, "Tempo & Tonhöhe", "Schneller oder langsamer mit gleicher Tonhöhe, Halbtöne und Cent."),
        (Icons.pitch, "Stimmung", "Kammerton erkennen und z. B. von 440 auf 432 Hz umstimmen."),
        (Icons.equalizer, "Equalizer", "10 Bänder und Bass – mit allen Voreinstellungen des Players."),
        ("mic", "Auto-Tune", "Gesang auf die Töne einer Tonart ziehen – am besten bei Einzelstimmen."),
    ]

    var body: some View {
        let rows = stride(from: 0, to: Self.tools.count, by: columns).map { Array(Self.tools[$0..<min($0 + columns, Self.tools.count)]) }
        VStack(spacing: 10) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(alignment: .top, spacing: 10) {
                    ForEach(rows[r], id: \.title) { tool in
                        HStack(alignment: .top, spacing: 10) {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(colors.accentSoft)
                                .frame(width: 34, height: 34)
                                .overlay(Icon(tool.icon, size: 18, color: colors.accentText))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tool.title)
                                    .textStyle(Typo.titleSmall)
                                    .foregroundColor(colors.textPrimary)
                                Text(tool.text)
                                    .textStyle(Typo.bodySmall)
                                    .foregroundColor(colors.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .glassSurface(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    }
                    if rows[r].count < columns {
                        ForEach(0..<(columns - rows[r].count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity) }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Werkzeuge des Studios")
    }
}
