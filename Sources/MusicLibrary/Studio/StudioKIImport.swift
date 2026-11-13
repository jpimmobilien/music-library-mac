import Foundation
import MLCore
import MLStudio

// KI-Musik → Musikbibliothek: Eine Kreation wird wie eine Datei in „Hinzufügen“ umgewandelt (Format, Ziel und
// Dateiname nach den Einstellungen dort) und erscheint in dessen Warteschlange und Verlauf. Die Kreation selbst
// bleibt unverändert im Ordner „KI-Musik“.

extension StudioModel {
    func importKICreation(file: URL, title: String, genre: String) {
        Task { [weak self] in
            guard let self else { return }
            do {
                var info = try await self.services.local.analyze(file: file)
                if info.localFile == nil { info.localFile = file }
                var meta = StudioMetadata(title: title, artist: "KI-Musik", genre: genre)
                meta.year = Calendar.current.component(.year, from: Date())
                info.title = title
                let opts = self.settings.options(for: self.settings.lastFormat)
                let job = StudioJob(source: info, options: opts, trim: nil, metadata: meta,
                                    fileName: self.batchScheme.render(meta, fallback: title), destination: self.settingsDestination)
                self.host.jobs.append(job)
                self.host.scheduleNext()
                self.lib?.studioToast("„\(title)“ wird in die Bibliothek übernommen (siehe „Hinzufügen“)", action: nil, isError: false, perform: nil)
            } catch {
                self.lib?.studioToast(StudioModel.message(error), action: nil, isError: true, perform: nil)
            }
        }
    }
}
