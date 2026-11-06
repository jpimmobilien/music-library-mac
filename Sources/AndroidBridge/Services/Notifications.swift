import Foundation
import UserNotifications

/// Mitteilungen bei abgeschlossenen Übertragungen (nur wenn eingeschaltet und das Fenster nicht vorne ist).
enum NotificationService {
    private static var authorized: Bool?
    /// In Snapshot-/Selbsttest-Läufen nichts anfragen.
    static var disabled = false

    static func post(title: String, body: String) {
        guard !disabled, Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        let send = {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
        if authorized == true {
            send()
            return
        }
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async {
                authorized = granted
                if granted { send() }
            }
        }
    }
}
