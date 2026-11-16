import SwiftUI
import AppKit
import PanoraCore

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var hardware: HardwareMonitor
    @EnvironmentObject private var experts: ExpertService
    @EnvironmentObject private var library: ModelLibrary
    @Environment(\.panora) private var colors

    var body: some View {
        PageScaffold(title: "Einstellungen", subtitle: "Panora arbeitet lokal. Alles hier bleibt auf diesem Mac.", bottomInset: 120) {
            EmptyView()
        } content: {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 420), spacing: 18, alignment: .top)], alignment: .leading, spacing: 18) {
                PanelCard(title: "AUTO MODE", systemImage: "wand.and.stars") {
                    Picker("Standard für neue Chats", selection: $settings.defaultMode) {
                        Text("Auto").tag(RoutingMode.auto)
                        Text("Manuell").tag(RoutingMode.manual)
                    }
                    .pickerStyle(.segmented)
                    Toggle("Im manuellen Modus Wechsel nach Rückfrage erlauben", isOn: $settings.allowSwitchInManual)
                    Text("Das manuell gewählte Modell wird nie heimlich ersetzt. Mit dieser Option schlägt Panora bessere Modelle nur vor.")
                        .font(Typo.label(12)).foregroundStyle(colors.textTertiary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Modellwechsel: \(settings.stickiness < 0.3 ? "häufig" : (settings.stickiness > 0.7 ? "zurückhaltend" : "ausgewogen"))")
                            .font(Typo.label(13)).foregroundStyle(colors.textSecondary)
                        Slider(value: $settings.stickiness, in: 0...1.2)
                    }
                    Toggle("Begründung der Modellwahl anzeigen", isOn: $settings.showRoutingDetails)
                    Toggle("Gedankengang der Modelle anzeigen", isOn: $settings.showReasoning)
                }
                PanelCard(title: "Speicher und Leistung", systemImage: "memorychip") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Modellbudget: \(Formatting.percent(settings.modelBudgetFraction)) = \(Formatting.bytes(Int64(Double(hardware.totalMemory) * settings.modelBudgetFraction)))")
                            .font(Typo.label(13)).foregroundStyle(colors.textSecondary)
                        Slider(value: $settings.modelBudgetFraction, in: 0.4...0.85, step: 0.05)
                        Text("Rest bleibt für macOS, Xcode, Android Studio und Emulatoren.").font(Typo.label(12)).foregroundStyle(colors.textTertiary)
                    }
                    Picker("Leerlauf: Modelle entladen nach", selection: $settings.idleUnloadMinutes) {
                        Text("5 Minuten").tag(5)
                        Text("20 Minuten").tag(20)
                        Text("1 Stunde").tag(60)
                        Text("Nie").tag(0)
                    }
                    Picker("Maximaler Kontext", selection: $settings.maxContextTokens) {
                        Text("8K").tag(8_192)
                        Text("16K").tag(16_384)
                        Text("32K").tag(32_768)
                        Text("64K").tag(65_536)
                        Text("128K").tag(131_072)
                    }
                    Picker("Maximale Antwortlänge", selection: $settings.maxAnswerTokens) {
                        Text("1.024 Tokens").tag(1024)
                        Text("4.096 Tokens").tag(4096)
                        Text("8.192 Tokens").tag(8192)
                        Text("16.384 Tokens").tag(16_384)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Kreativität (Temperatur): \(Formatting.decimal(settings.temperature, digits: 1))").font(Typo.label(13)).foregroundStyle(colors.textSecondary)
                        Slider(value: $settings.temperature, in: 0...1.2, step: 0.1)
                    }
                }
                PanelCard(title: "Externe Experten (optional)", systemImage: "cloud") {
                    Toggle("Zweitmeinung von ChatGPT oder Claude erlauben", isOn: $settings.expertsEnabled)
                    Text("Keine automatische Cloud-Nutzung. Vor jedem Senden zeigt Panora genau, welcher Text den Mac verlässt. Die APIs werden separat über dein Konto abgerechnet; Grundfunktionen brauchen sie nie.")
                        .font(Typo.label(12)).foregroundStyle(colors.textTertiary)
                    if settings.expertsEnabled {
                        ForEach(ExpertProvider.allCases) { p in ExpertKeyEditor(provider: p) }
                    }
                }
                PanelCard(title: "Rechenwerke", systemImage: "gearshape.2") {
                    Text("MLX ist eingebaut und für Apple Silicon optimiert.").font(Typo.label(12.5)).foregroundStyle(colors.textSecondary)
                    Toggle("Ollama-Modelle mitnutzen (falls installiert)", isOn: $settings.ollamaEnabled)
                    if settings.ollamaEnabled {
                        TextField("Adresse", text: $settings.ollamaURL).textFieldStyle(.roundedBorder)
                        Text(library.ollamaRunning ? "Ollama läuft." : "Ollama wurde nicht gefunden.").font(Typo.label(12)).foregroundStyle(colors.textTertiary)
                    }
                }
                PanelCard(title: "Darstellung", systemImage: "paintbrush") {
                    Picker("Erscheinungsbild", selection: $settings.appearance) {
                        ForEach(AppearanceMode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Glas-Effekte (Liquid Glass)", isOn: $settings.glassEffects)
                }
                PanelCard(title: "Offline", systemImage: "wifi.slash") {
                    Toggle("Offline-Modus erzwingen (keine Netzwerkzugriffe)", isOn: $settings.forceOffline)
                    Text("Chat, Projektanalyse und installierte Modelle funktionieren immer ohne Internet. Offline sind nur Downloads, die Suche auf Hugging Face und externe Experten nicht verfügbar.")
                        .font(Typo.label(12)).foregroundStyle(colors.textTertiary)
                }
                PanelCard(title: "Über Panora", systemImage: "info.circle") {
                    InfoRow(label: "Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1")
                    InfoRow(label: "Build", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1")
                    InfoRow(label: "Mac", value: "\(hardware.chipName) · \(hardware.modelIdentifier)")
                    Text("Panora ist ein lokaler KI-Assistent: eigene Aufgabenerkennung, eigenes Modellrouting, eigene Kontextverwaltung. MLX und Ollama sind nur Rechenwerke.")
                        .font(Typo.label(12)).foregroundStyle(colors.textTertiary)
                }
            }
            .toggleStyle(.switch)
        }
    }
}

private struct ExpertKeyEditor: View {
    @EnvironmentObject private var experts: ExpertService
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.panora) private var colors
    let provider: ExpertProvider
    @State private var key = ""
    @State private var models: [String] = []
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(provider.label).font(Typo.body(13.5, .semibold)).foregroundStyle(colors.textPrimary)
                Spacer()
                Badge(text: experts.hasKey(provider) ? "Schlüssel im Schlüsselbund" : "kein Schlüssel",
                      color: experts.hasKey(provider) ? colors.success : colors.textTertiary)
            }
            HStack {
                SecureField(experts.hasKey(provider) ? "Neuen Schlüssel eingeben" : "API-Schlüssel (\(provider.keyHint))", text: $key)
                    .textFieldStyle(.roundedBorder)
                Button("Speichern") { experts.setKey(provider, key); key = "" }.disabled(key.isEmpty)
                if experts.hasKey(provider) { Button("Löschen") { experts.setKey(provider, "") } }
            }
            HStack {
                TextField("Modell", text: provider == .openAI ? $settings.openAIModel : $settings.anthropicModel)
                    .textFieldStyle(.roundedBorder)
                Menu("Modelle abrufen") {
                    if models.isEmpty { Text("Noch nicht abgerufen") }
                    ForEach(models, id: \.self) { m in
                        Button(m) { if provider == .openAI { settings.openAIModel = m } else { settings.anthropicModel = m } }
                    }
                }
                .fixedSize()
                .disabled(!experts.hasKey(provider))
                .simultaneousGesture(TapGesture().onEnded { load() })
            }
            if let message { Text(message).font(Typo.label(11.5)).foregroundStyle(colors.textTertiary) }
            Link("Schlüssel erstellen", destination: URL(string: provider.consoleURL)!).font(Typo.label(12))
        }
        .padding(.top, 6)
    }

    private func load() {
        guard models.isEmpty, experts.hasKey(provider) else { return }
        Task {
            do { models = try await experts.fetchModels(provider) }
            catch { message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
        }
    }
}
