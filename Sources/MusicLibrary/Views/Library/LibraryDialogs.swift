import SwiftUI
import AppKit
import MLCore
import MLTags

// Glas-Blätter der Bibliothek (v2.1): Löschen mit klarer Wahl zwischen „Aus der Musikbibliothek entfernen“
// und „In den Papierkorb legen“ sowie „Als Album zusammenfassen …“. Beide erscheinen als Blatt am
// Hauptfenster und lassen sich von überall aus öffnen (Kontextmenüs, Auswahlleiste, Entf-Taste).

// MARK: - Blatt am Hauptfenster

@MainActor
enum GlassSheet {
    /// Offene Blätter (bis zum Schließen festhalten).
    private static var open: [NSWindow] = []

    /// Zeigt `content` als Blatt am Hauptfenster (sonst am aktiven Fenster). `content` erhält eine Funktion
    /// zum Schließen.
    static func present<Content: View>(width: CGFloat, @ViewBuilder content: (@escaping () -> Void) -> Content) {
        guard let model = AppModel.shared else { return }
        let parent: NSWindow? = {
            if let main = MainWindowRef.window, main.isVisible { return main }
            return NSApp.keyWindow ?? NSApp.mainWindow
        }()
        // Ein Blatt nach dem anderen
        if let parent, parent.attachedSheet != nil { return }
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 200),
                             styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: true)
        sheet.titlebarAppearsTransparent = true
        sheet.titleVisibility = .hidden
        sheet.isReleasedWhenClosed = false
        // Erscheinungsbild des Hauptfensters übernehmen (Einstellung Hell/Dunkel gilt auch im Blatt)
        if let parent { sheet.appearance = parent.effectiveAppearance }
        let close: () -> Void = { [weak sheet] in
            guard let sheet else { return }
            if let p = sheet.sheetParent { p.endSheet(sheet) } else { sheet.orderOut(nil) }
            open.removeAll { $0 === sheet }
        }
        let body = content(close)
        let root = ThemedRoot(model: model) {
            body
                .frame(width: width)
                .fixedSize(horizontal: false, vertical: true)
        }
        let host = NSHostingView(rootView: root)
        sheet.contentView = host
        sheet.setContentSize(host.fittingSize)
        open.append(sheet)
        if let parent {
            parent.beginSheet(sheet, completionHandler: nil)
        } else {
            sheet.center()
            sheet.makeKeyAndOrderFront(nil)
        }
    }
}

/// Unsichtbare Schaltfläche für Esc (eine sichtbare Schaltfläche kann nur ein Tastenkürzel tragen).
private struct EscapeButton: View {
    let action: () -> Void

    var body: some View {
        Button("Abbrechen", action: action)
            .keyboardShortcut(.cancelAction)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }
}

// MARK: - Löschen

/// Was gelöscht wird – für eine eindeutige Überschrift.
enum DeleteSubject: Equatable {
    case tracks
    case album(title: String)
    case albums(count: Int)
    /// z. B. „Interpret „Queen““ oder „3 Interpreten“.
    case group(label: String)
}

extension DeleteSubject {
    /// Beschreibung für gewählte Einträge einer Sammlung.
    static func groups(_ kind: LibrarySelectionKind, count: Int, firstName: String?) -> DeleteSubject {
        let name = firstName ?? ""
        switch kind {
        case .tracks: return .tracks
        case .albums: return count == 1 ? .album(title: name.isEmpty ? "Unbekanntes Album" : name) : .albums(count: count)
        case .artists: return count == 1 ? .group(label: "Interpret „\(name)“") : .group(label: Formatting.artists(count))
        case .genres: return count == 1 ? .group(label: "Genre „\(name)“") : .group(label: Formatting.genres(count))
        case .playlists: return count == 1 ? .group(label: "Playlist „\(name)“") : .group(label: Formatting.playlists(count))
        }
    }
}

/// Löschen von Titeln: „Aus der Musikbibliothek entfernen“ (Datei bleibt) oder „In den Papierkorb legen“
/// (mit zweiter Bestätigung). „Abbrechen“ ist Standard (Eingabe und Esc) – Eingabe löst nie etwas
/// Unwiderrufliches aus.
enum RemoveTracksDialog {
    @MainActor
    static func present(model: AppModel, uids: [Int64], subject: DeleteSubject = .tracks) {
        var seen = Set<Int64>()
        let unique = uids.filter { seen.insert($0).inserted }
        guard !unique.isEmpty else { return }
        GlassSheet.present(width: 470) { close in
            DeleteTracksDialogView(uids: unique, subject: subject, close: close)
        }
    }
}

/// Inhalt des Löschdialogs (auch für Vorschaubilder: `DeleteTracksDialogView(uids:subject:close:)`).
struct DeleteTracksDialogView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.musicColors) private var colors
    let uids: [Int64]
    let subject: DeleteSubject
    let close: () -> Void
    /// Zweiter Schritt „In den Papierkorb legen?“ (Vorschaubilder können direkt damit beginnen).
    @State var confirmTrash: Bool = false

    var body: some View {
        let tracks = model.tracks(uids)
        let files = Set(tracks.map(\.path)).count
        let reachable = tracks.filter(\.available)
        let reachableFiles = Set(reachable.map(\.path)).count
        // Beide Schritte liegen übereinander → das Blatt ändert seine Größe nicht.
        ZStack(alignment: .topLeading) {
            choose(tracks: tracks, files: files, reachableFiles: reachableFiles)
                .opacity(confirmTrash ? 0 : 1)
                .allowsHitTesting(!confirmTrash)
                .disabled(confirmTrash)
                .accessibilityHidden(confirmTrash)
            confirm(reachable: reachable, reachableFiles: reachableFiles)
                .opacity(confirmTrash ? 1 : 0)
                .allowsHitTesting(confirmTrash)
                .disabled(!confirmTrash)
                .accessibilityHidden(!confirmTrash)
        }
        .padding(22)
        .background(AmbientBackground())
        .animation(Motion.easeOut(Motion.short), value: confirmTrash)
    }

    // MARK: Schritt 1: Wahl

    private func choose(tracks: [Track], files: Int, reachableFiles: Int) -> some View {
        let unreachable = files - reachableFiles
        return VStack(alignment: .leading, spacing: 0) {
            Text(headline(tracks))
                .textStyle(Typo.titleLarge)
                .foregroundColor(colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(scope(tracks: tracks.count, files: files))
                .textStyle(Typo.bodyMedium)
                .foregroundColor(colors.textSecondary)
                .padding(.top, 4)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 10) {
                DeleteOption(
                    icon: Icons.libraryMusic,
                    title: "Aus der Musikbibliothek entfernen",
                    text: "Nur die Einträge in der Bibliothek werden entfernt. \(filesPhrase(files, capitalized: true)) \(files == 1 ? "bleibt" : "bleiben") unverändert auf deinem Mac und \(files == 1 ? "wird" : "werden") beim nächsten Einlesen nicht wieder aufgenommen. Direkt danach lässt sich das rückgängig machen.",
                    destructive: false
                ) {
                    close()
                    model.removeTracks(uids, moveFilesToTrash: false)
                }
                DeleteOption(
                    icon: Icons.delete,
                    title: "In den Papierkorb legen",
                    text: trashText(files: files, reachableFiles: reachableFiles),
                    destructive: true
                ) {
                    confirmTrash = true
                }
                .disabled(reachableFiles == 0)
            }
            .padding(.top, 16)
            if unreachable > 0 {
                HStack(alignment: .top, spacing: 7) {
                    Icon(Icons.warning, size: 14, color: colors.textSecondary)
                    Text("\(filesPhrase(unreachable, capitalized: true)) \(unreachable == 1 ? "ist" : "sind") gerade nicht erreichbar (z. B. Laufwerk getrennt) und \(unreachable == 1 ? "kann" : "können") nicht in den Papierkorb gelegt werden.")
                        .textStyle(Typo.bodySmall)
                        .foregroundColor(colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 10)
            }
            HStack {
                Spacer()
                PillButton(title: "Abbrechen", minWidth: 110) { close() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 18)
            EscapeButton { close() }
        }
    }

    // MARK: Schritt 2: Papierkorb bestätigen

    private func confirm(reachable: [Track], reachableFiles: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(colors.danger.opacity(0.14))
                    .frame(width: 48, height: 48)
                    .overlay(Icon(Icons.delete, size: 24, color: colors.danger))
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(filesPhrase(reachableFiles, capitalized: true)) in den Papierkorb legen?")
                        .textStyle(Typo.titleLarge)
                        .foregroundColor(colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Du kannst sie im Finder aus dem Papierkorb zurückholen. \(reachable.count == 1 ? "Der Titel wird" : "Die Titel werden") aus der Bibliothek gelöscht.")
                        .textStyle(Typo.bodyMedium)
                        .foregroundColor(colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 18)
            HStack(spacing: 10) {
                Spacer()
                PillButton(title: "Abbrechen", minWidth: 110) { close() }
                    .keyboardShortcut(.defaultAction)
                DangerPillButton(title: "In den Papierkorb legen", icon: Icons.delete) {
                    close()
                    model.removeTracks(reachable.map(\.uid), moveFilesToTrash: true)
                }
            }
            EscapeButton { close() }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: Texte

    private func headline(_ tracks: [Track]) -> String {
        switch subject {
        case .tracks:
            if tracks.count == 1, let t = tracks.first { return "„\(t.displayTitle)“ löschen?" }
            return "\(Formatting.tracks(tracks.count)) löschen?"
        case .album(let title): return "Album „\(title)“ löschen?"
        case .albums(let count): return "\(Formatting.albums(count)) löschen?"
        case .group(let label): return "\(label) löschen?"
        }
    }

    /// „Album „X“ – 12 Titel, 12 Dateien“.
    private func scope(tracks: Int, files: Int) -> String {
        let counts = "\(Formatting.tracks(tracks)), \(filesPhrase(files, capitalized: false))"
        switch subject {
        case .tracks: return counts
        case .album(let title): return "Album „\(title)“ – \(counts)"
        case .albums(let count): return "\(Formatting.albums(count)) – \(counts)"
        case .group(let label): return "\(label) – \(counts)"
        }
    }

    private func trashText(files: Int, reachableFiles: Int) -> String {
        if reachableFiles == 0 { return "Keine der Dateien ist gerade erreichbar." }
        let all = reachableFiles == files ? (files == 1 ? "Die Datei" : "Alle \(Formatting.integer(files)) Dateien") : filesPhrase(reachableFiles, capitalized: true)
        return "\(all) \(reachableFiles == 1 ? "wird" : "werden") in den Papierkorb des Macs gelegt und aus der Bibliothek gelöscht. Im Finder lassen sie sich aus dem Papierkorb zurückholen. Du wirst noch einmal gefragt."
    }

    private func filesPhrase(_ count: Int, capitalized: Bool) -> String {
        if count == 1 { return capitalized ? "Die Datei" : "1 Datei" }
        return "\(Formatting.integer(count)) Dateien"
    }
}

/// Große Wahlfläche im Löschdialog: Symbol, Titel, Erklärung.
private struct DeleteOption: View {
    @Environment(\.musicColors) private var colors
    @Environment(\.isEnabled) private var enabled
    let icon: String
    let title: String
    let text: String
    let destructive: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        let tint = destructive ? colors.danger : colors.accentText
        let shape = RoundedRectangle(cornerRadius: Radius.card - 4, style: .continuous)
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(0.13))
                    .frame(width: 36, height: 36)
                    .overlay(Icon(icon, size: 19, color: tint))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(Typo.inter(14, .semibold))
                        .foregroundColor(destructive ? colors.danger : colors.textPrimary)
                    Text(text)
                        .textStyle(Typo.bodySmall)
                        .foregroundColor(colors.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Icon(Icons.chevronRight, size: 16, color: colors.textTertiary)
                    .padding(.top, 10)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(colors.textPrimary.opacity(hover && enabled ? 0.06 : 0.02)))
            .overlay(shape.strokeBorder(destructive ? colors.danger.opacity(hover ? 0.55 : 0.3) : colors.hairline, lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(PressScaleStyle(scale: 0.98))
        .onHover { hover = $0 }
        .opacity(enabled ? 1 : 0.45)
        .accessibilityLabel(title)
        .accessibilityHint(text)
    }
}

/// Rote Kapsel für die endgültige, zerstörerische Aktion.
private struct DangerPillButton: View {
    @Environment(\.musicColors) private var colors
    let title: String
    var icon: String? = nil
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Icon(icon, size: 16, color: .white) }
                Text(title)
                    .textStyle(Typo.labelLarge)
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: Metrics.pillHeight)
            .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(colors.danger))
            .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(Color.white.opacity(hover ? 0.1 : 0)))
            .contentShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        }
        .buttonStyle(PressScaleStyle(scale: 0.96))
        .onHover { hover = $0 }
    }
}

// MARK: - Als Album zusammenfassen

enum MergeAlbumDialog {
    @MainActor
    static func present(model: AppModel, uids: [Int64]) {
        var seen = Set<Int64>()
        let unique = uids.filter { seen.insert($0).inserted }
        guard unique.count > 0 else { return }
        GlassSheet.present(width: 500) { close in
            MergeAlbumSheet(uids: unique, close: close)
        }
    }
}

/// „Als Album zusammenfassen …“: setzt Album (Pflicht) und auf Wunsch Album-Interpret, Jahr, Genre,
/// Compilation sowie fortlaufende Titelnummern – **nur** diese Felder. Ein Feld wird nur geschrieben, wenn es
/// geändert wurde; ein leer gelassenes Feld bleibt unangetastet, außer ein vorhandener Wert wurde bewusst
/// gelöscht.
struct MergeAlbumSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.musicColors) private var colors
    let uids: [Int64]
    let close: () -> Void

    @State private var loaded = false
    @State private var initial = MergeFields()
    @State private var fields = MergeFields()
    @State private var renumber = false
    @State private var alignDiscs = false
    @FocusState private var albumFocused: Bool

    var body: some View {
        let tracks = model.tracks(uids)
        let writable = tracks.filter(\.available)
        let discs = Set(writable.map { $0.discNumber ?? 1 })
        VStack(alignment: .leading, spacing: 0) {
            header(tracks.count)
            VStack(alignment: .leading, spacing: 10) {
                MergeField(label: "Album", placeholder: "Name des Albums (Pflicht)", text: $fields.album,
                           hint: fields.album.trimmingCharacters(in: .whitespaces).isEmpty ? "Bitte einen Albumnamen eingeben." : nil,
                           focus: $albumFocused)
                MergeField(label: "Album-Interpret", placeholder: placeholder(initial.albumArtistMixed), text: $fields.albumArtist,
                           hint: clearedHint(\.albumArtist))
                HStack(alignment: .top, spacing: 10) {
                    MergeField(label: "Jahr", placeholder: placeholder(initial.yearMixed), text: $fields.year,
                               hint: yearValid ? clearedHint(\.year) : "Jahr als Zahl, z. B. 1997.")
                        .frame(width: 150)
                    MergeField(label: "Genre", placeholder: placeholder(initial.genreMixed), text: $fields.genre,
                               hint: clearedHint(\.genre))
                }
            }
            .padding(.top, 16)
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $fields.compilation) {
                    Text(initial.compilationMixed && fields.compilation == initial.compilation
                         ? "Compilation (verschiedene Interpreten) – derzeit unterschiedlich, bleibt so"
                         : "Compilation (verschiedene Interpreten)")
                        .textStyle(Typo.bodyMedium)
                        .foregroundColor(colors.textPrimary)
                }
                .toggleStyle(.checkbox)
                Toggle(isOn: $renumber) {
                    Text("Titelnummern fortlaufend vergeben (1 bis \(writable.count), in der angezeigten Reihenfolge)")
                        .textStyle(Typo.bodyMedium)
                        .foregroundColor(colors.textPrimary)
                }
                .toggleStyle(.checkbox)
                if renumber && discs.count > 1 {
                    Toggle(isOn: $alignDiscs) {
                        Text("Disc-Angaben angleichen (alle „Disc 1 von 1“) – sonst sortieren sich die Discs getrennt")
                            .textStyle(Typo.bodySmall)
                            .foregroundColor(colors.textSecondary)
                    }
                    .toggleStyle(.checkbox)
                    .padding(.leading, 20)
                }
            }
            .padding(.top, 16)
            footer(total: tracks.count, writable: writable)
        }
        .padding(22)
        .background(AmbientBackground())
        .onAppear { load(tracks) }
    }

    private func header(_ count: Int) -> some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(colors.accentSoft)
                .frame(width: 48, height: 48)
                .overlay(Icon(Icons.album, size: 24, color: colors.accentText))
            VStack(alignment: .leading, spacing: 3) {
                Text("Als Album zusammenfassen")
                    .textStyle(Typo.titleLarge)
                    .foregroundColor(colors.textPrimary)
                Text("\(Formatting.tracks(count)) erhalten dieselben Albumangaben. Geschrieben werden nur die Felder, die du hier änderst – alle übrigen Angaben bleiben, wie sie sind.")
                    .textStyle(Typo.bodySmall)
                    .foregroundColor(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func footer(total: Int, writable: [Track]) -> some View {
        let skipped = total - writable.count
        let canSave = !fields.album.trimmingCharacters(in: .whitespaces).isEmpty && yearValid && !writable.isEmpty
        return VStack(alignment: .leading, spacing: 8) {
            if skipped > 0 {
                Text("\(Formatting.tracks(skipped)) \(skipped == 1 ? "ist" : "sind") gerade nicht erreichbar und \(skipped == 1 ? "wird" : "werden") übersprungen.")
                    .textStyle(Typo.bodySmall)
                    .foregroundColor(colors.textSecondary)
            }
            Text("Jede Datei wird vorher gesichert; die Änderung lässt sich rückgängig machen.")
                .textStyle(Typo.labelMedium)
                .foregroundColor(colors.textTertiary)
            HStack(spacing: 10) {
                Spacer()
                PillButton(title: "Abbrechen", minWidth: 110) { close() }
                PillButton(title: "Zusammenfassen", icon: Icons.check, style: .filled, minWidth: 150) { save(writable) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(.top, 6)
            EscapeButton { close() }
        }
        .padding(.top, 18)
    }

    private var yearValid: Bool {
        let y = fields.year.trimmingCharacters(in: .whitespaces)
        return y.isEmpty || (y.count <= 4 && y.allSatisfy(\.isNumber))
    }

    private func placeholder(_ mixed: Bool) -> String {
        mixed ? "Unterschiedlich – bleibt unverändert" : "Leer – bleibt unverändert"
    }

    /// Hinweis, wenn ein vorhandener Wert gelöscht wurde (wird dann wirklich entfernt).
    private func clearedHint(_ key: KeyPath<MergeFields, String>) -> String? {
        let now = fields[keyPath: key].trimmingCharacters(in: .whitespaces)
        let before = initial[keyPath: key].trimmingCharacters(in: .whitespaces)
        return now.isEmpty && !before.isEmpty ? "Wird bei allen Titeln entfernt." : nil
    }

    // MARK: Werte

    private func load(_ tracks: [Track]) {
        guard !loaded else { return }
        loaded = true
        var f = MergeFields()
        f.album = Self.mostFrequent(tracks.compactMap(\.album)) ?? ""
        let artists = tracks.map { $0.albumArtists.joined(separator: "; ") }
        f.albumArtistMixed = Set(artists).count > 1
        f.albumArtist = f.albumArtistMixed ? "" : (artists.first ?? "")
        let years = tracks.map { $0.year.map { String($0) } ?? "" }
        f.yearMixed = Set(years).count > 1
        f.year = f.yearMixed ? "" : (years.first ?? "")
        let genres = tracks.map { $0.genres.joined(separator: "; ") }
        f.genreMixed = Set(genres).count > 1
        f.genre = f.genreMixed ? "" : (genres.first ?? "")
        let compilations = Set(tracks.map(\.compilation))
        f.compilationMixed = compilations.count > 1
        f.compilation = compilations.count == 1 ? (compilations.first ?? false) : false
        initial = f
        fields = f
        DispatchQueue.main.async { albumFocused = true }
    }

    private static func mostFrequent(_ values: [String]) -> String? {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for v in values where !v.isEmpty {
            if counts[v] == nil { order.append(v) }
            counts[v, default: 0] += 1
        }
        return order.max { (counts[$0] ?? 0) < (counts[$1] ?? 0) }
    }

    /// Schreibt nur die gewählten Felder (über die sichere Schreibstrategie mit Sicherung und Rückgängig).
    private func save(_ tracks: [Track]) {
        let album = fields.album.trimmingCharacters(in: .whitespaces)
        guard !album.isEmpty, yearValid, !tracks.isEmpty else { return }
        var values = TagValues()
        var written: Set<TagField> = [.album]
        values.setText(album, for: .album)
        if fields.albumArtist != initial.albumArtist {
            values.setText(fields.albumArtist, for: .albumArtists)
            written.insert(.albumArtists)
        }
        if fields.year != initial.year {
            values.setText(fields.year, for: .year)
            written.insert(.year)
        }
        if fields.genre != initial.genre {
            values.setText(fields.genre, for: .genres)
            written.insert(.genres)
        }
        if fields.compilation != initial.compilation {
            values.compilation = fields.compilation
            written.insert(.compilation)
        }
        if renumber {
            written.insert(.trackNumber)
            written.insert(.trackTotal)
            values.trackTotal = tracks.count
            let discs = Set(tracks.map { $0.discNumber ?? 1 })
            if alignDiscs && discs.count > 1 {
                written.insert(.discNumber)
                written.insert(.discTotal)
                values.discNumber = 1
                values.discTotal = 1
            }
        }
        var requests: [(uid: Int64, request: TagWriteRequest)] = []
        requests.reserveCapacity(tracks.count)
        for (i, t) in tracks.enumerated() {
            var v = values
            if renumber { v.trackNumber = i + 1 }
            let edit = TagEdit(values: v, fields: written)
            requests.append((uid: t.uid, request: TagWriteRequest(url: URL(fileURLWithPath: t.path), edit: edit)))
        }
        close()
        LibrarySelectionStore.shared.clear()
        let metadata = model.metadata
        let batch = requests
        let label = "Album „\(album)“"
        Task { _ = await metadata.write(batch, label: label) }
    }
}

/// Werte des Zusammenfassen-Blatts (Text wie eingegeben; „gemischt“ = unterschiedliche Werte in der Auswahl).
struct MergeFields: Equatable {
    var album = ""
    var albumArtist = ""
    var albumArtistMixed = false
    var year = ""
    var yearMixed = false
    var genre = ""
    var genreMixed = false
    var compilation = false
    var compilationMixed = false
}

/// Beschriftetes Eingabefeld im Stil des Suchfelds.
private struct MergeField: View {
    @Environment(\.musicColors) private var colors
    let label: String
    let placeholder: String
    @Binding var text: String
    var hint: String? = nil
    var focus: FocusState<Bool>.Binding? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(Typo.inter(10.5, .semibold))
                .tracking(0.5)
                .foregroundColor(colors.textTertiary)
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(placeholder)
                        .textStyle(Typo.bodyLarge)
                        .foregroundColor(colors.textTertiary)
                        .lineLimit(1)
                        .allowsHitTesting(false)
                }
                field
            }
            .padding(.horizontal, 10)
            .frame(height: Metrics.searchFieldHeight)
            .background(RoundedRectangle(cornerRadius: Radius.control - 2, style: .continuous).fill(colors.fieldFill))
            if let hint {
                Text(hint)
                    .textStyle(Typo.labelSmall)
                    .foregroundColor(colors.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var field: some View {
        if let focus {
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .textStyle(Typo.bodyLarge)
                .foregroundColor(colors.textPrimary)
                .focused(focus)
                .accessibilityLabel(label)
        } else {
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .textStyle(Typo.bodyLarge)
                .foregroundColor(colors.textPrimary)
                .accessibilityLabel(label)
        }
    }
}
