import Foundation
import ABCore

/// Verständliche Fehlermeldung mit empfohlener Maßnahme; technische Details nur zusätzlich.
struct ABIssue: Identifiable, Equatable, Error {
    enum Kind: String {
        case deviceNotDetected, cableWithoutData, chargingOnly, authorization, mtpInitFailed, deviceBusy, disconnected
        case storageUnavailable, permissionDenied, fileNotFound, insufficientMacSpace, insufficientDeviceSpace
        case destinationWriteFailed, conflict, unsupportedOperation, incompleteTransfer, unsupportedProtocol, timeout, general
    }

    let id = UUID()
    var kind: Kind
    var title: String
    var message: String
    var recommendation: String?
    var technical: String?

    static func == (a: ABIssue, b: ABIssue) -> Bool { a.id == b.id }

    var symbolName: String {
        switch kind {
        case .disconnected, .deviceNotDetected, .cableWithoutData: return "cable.connector.slash"
        case .chargingOnly: return "bolt.fill"
        case .authorization: return "lock.iphone"
        case .deviceBusy: return "hourglass"
        case .insufficientMacSpace, .insufficientDeviceSpace: return "externaldrive.badge.exclamationmark"
        case .permissionDenied: return "hand.raised"
        case .conflict: return "doc.on.doc"
        default: return "exclamationmark.triangle"
        }
    }

    static func from(_ error: Error, context: String? = nil) -> ABIssue {
        if let issue = error as? ABIssue { return issue }
        if let mtp = error as? MTPError { return from(mtp, context: context) }
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain {
            switch ns.code {
            case NSFileWriteOutOfSpaceError:
                return ABIssue(kind: .insufficientMacSpace, title: "Nicht genug Speicherplatz auf dem Mac",
                               message: "Die Datei passt nicht mehr auf das Ziellaufwerk.",
                               recommendation: "Schaffen Sie Platz oder wählen Sie ein anderes Ziel.", technical: ns.description)
            case NSFileWriteNoPermissionError, NSFileReadNoPermissionError:
                return ABIssue(kind: .permissionDenied, title: "Keine Berechtigung",
                               message: "macOS erlaubt den Zugriff auf diesen Ordner nicht.",
                               recommendation: "Wählen Sie einen anderen Ordner oder erlauben Sie den Zugriff in den Systemeinstellungen unter Datenschutz & Sicherheit → Dateien und Ordner.",
                               technical: ns.description)
            case NSFileNoSuchFileError, NSFileReadNoSuchFileError:
                return ABIssue(kind: .fileNotFound, title: "Datei nicht gefunden",
                               message: "Die Datei existiert nicht mehr.", recommendation: "Aktualisieren Sie die Ansicht.",
                               technical: ns.description)
            case NSFileWriteVolumeReadOnlyError:
                return ABIssue(kind: .destinationWriteFailed, title: "Ziel ist schreibgeschützt",
                               message: "Auf dieses Laufwerk kann nicht geschrieben werden.",
                               recommendation: "Wählen Sie ein anderes Ziel.", technical: ns.description)
            default:
                break
            }
        }
        return ABIssue(kind: .general, title: context ?? "Vorgang fehlgeschlagen",
                       message: ns.localizedDescription, recommendation: nil, technical: "\(ns.domain) \(ns.code)")
    }

    static func from(_ e: MTPError, context: String? = nil) -> ABIssue {
        switch e {
        case .disconnected:
            return ABIssue(kind: .disconnected, title: "Verbindung unterbrochen",
                           message: "Das Android-Gerät wurde getrennt oder antwortet nicht mehr.",
                           recommendation: "Prüfen Sie das Kabel, entsperren Sie das Telefon und schließen Sie es erneut an.",
                           technical: e.description)
        case .busy:
            return ABIssue(kind: .deviceBusy, title: "Gerät wird von einem anderen Programm verwendet",
                           message: "Ein anderes Programm – meist der macOS-Fotodienst (Digitale Bilder/Fotos) oder ein anderes Android-Programm – hält die Verbindung.",
                           recommendation: "Schließen Sie andere Programme oder lassen Sie Android Bridge den macOS-Fotodienst kurz freigeben.",
                           technical: e.description)
        case .accessDenied:
            return ABIssue(kind: .authorization, title: "Zugriff nicht erlaubt",
                           message: "Das Telefon erlaubt den Zugriff derzeit nicht.",
                           recommendation: "Entsperren Sie das Telefon und bestätigen Sie ggf. die Abfrage zur Dateiübertragung.",
                           technical: e.description)
        case .timeout:
            return ABIssue(kind: .timeout, title: "Das Telefon antwortet nicht",
                           message: "Die Anfrage hat zu lange gedauert.",
                           recommendation: "Entsperren Sie das Telefon. Hilft das nicht, trennen Sie das Kabel kurz.",
                           technical: e.description)
        case .cancelled:
            return ABIssue(kind: .general, title: "Abgebrochen", message: "Der Vorgang wurde abgebrochen.", technical: nil)
        case let .incomplete(expected, received):
            return ABIssue(kind: .incompleteTransfer, title: "Übertragung unvollständig",
                           message: "Es kamen nur \(ByteFormat.string(received)) von \(ByteFormat.string(expected)) an.",
                           recommendation: "Wiederholen Sie die Übertragung.", technical: e.description)
        case .notSupported(let what):
            return ABIssue(kind: .unsupportedOperation, title: "Nicht unterstützt",
                           message: "Das Gerät unterstützt diesen Vorgang nicht (\(what)).", technical: e.description)
        case .protocolError:
            return ABIssue(kind: .mtpInitFailed, title: "Kommunikationsfehler",
                           message: "Das Gerät hat unerwartet geantwortet.",
                           recommendation: "Trennen Sie das Telefon kurz und schließen Sie es erneut an.", technical: e.description)
        case .transport:
            return ABIssue(kind: .mtpInitFailed, title: "USB-Fehler",
                           message: "Die USB-Kommunikation ist fehlgeschlagen.",
                           recommendation: "Verwenden Sie möglichst ein anderes Kabel oder einen anderen Anschluss.", technical: e.description)
        case .response(let code):
            switch PTPResponse(rawValue: code) {
            case .storeFull?:
                return ABIssue(kind: .insufficientDeviceSpace, title: "Telefonspeicher voll",
                               message: "Auf dem Android-Gerät ist nicht genug Platz.",
                               recommendation: "Schaffen Sie Platz auf dem Telefon oder wählen Sie die SD-Karte.", technical: e.description)
            case .storeNotAvailable?, .invalidStorageID?:
                return ABIssue(kind: .storageUnavailable, title: "Speicher nicht verfügbar",
                               message: "Der Speicher (z. B. die SD-Karte) ist nicht mehr erreichbar.",
                               recommendation: "Prüfen Sie die SD-Karte und aktualisieren Sie die Ansicht.", technical: e.description)
            case .accessDenied?, .objectWriteProtected?, .storeReadOnly?:
                return ABIssue(kind: .permissionDenied, title: "Zugriff verweigert",
                               message: "Android erlaubt diesen Vorgang an dieser Stelle nicht (z. B. geschützte App-Ordner).",
                               recommendation: "Wählen Sie einen anderen Ordner, etwa „Download“ oder „Documents“.", technical: e.description)
            case .invalidObjectHandle?:
                return ABIssue(kind: .fileNotFound, title: "Datei nicht mehr vorhanden",
                               message: "Die Datei wurde auf dem Telefon inzwischen geändert oder gelöscht.",
                               recommendation: "Aktualisieren Sie die Ansicht.", technical: e.description)
            case .operationNotSupported?, .parameterNotSupported?, .objectPropNotSupported?:
                return ABIssue(kind: .unsupportedOperation, title: "Vom Gerät nicht unterstützt",
                               message: "Dieses Telefon unterstützt den Vorgang nicht.", technical: e.description)
            case .deviceBusy?:
                return ABIssue(kind: .deviceBusy, title: "Telefon ist beschäftigt",
                               message: "Das Telefon bearbeitet noch eine andere Anfrage.",
                               recommendation: "Versuchen Sie es in einigen Sekunden erneut.", technical: e.description)
            case .incompleteTransfer?:
                return ABIssue(kind: .incompleteTransfer, title: "Übertragung unvollständig",
                               message: "Das Telefon meldet eine unvollständige Übertragung.",
                               recommendation: "Wiederholen Sie die Übertragung.", technical: e.description)
            default:
                return ABIssue(kind: .general, title: context ?? "Vorgang fehlgeschlagen",
                               message: "Das Telefon hat den Vorgang abgelehnt.",
                               recommendation: "Versuchen Sie es erneut oder trennen Sie das Telefon kurz.", technical: e.description)
            }
        }
    }

    static let chargingOnly = ABIssue(
        kind: .chargingOnly, title: "Dateiübertragung ist nicht eingeschaltet",
        message: "Das Telefon ist verbunden, lädt aber nur.",
        recommendation: "Entsperren Sie Ihr Android-Gerät und wählen Sie in den USB-Einstellungen „Dateiübertragung / Android Auto“.",
        technical: nil)

    static let locked = ABIssue(
        kind: .authorization, title: "Telefon entsperren",
        message: "Das Telefon gibt seinen Speicher erst frei, wenn es entsperrt ist.",
        recommendation: "Entsperren Sie das Telefon. Erscheint dort eine Abfrage, erlauben Sie den Zugriff.",
        technical: nil)
}
