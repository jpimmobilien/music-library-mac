import SwiftUI
import AppKit

// Menüs im App-Stil als Glas-Popover.
//
// Warum nicht `Menu`? macOS stellt die Beschriftung eines `Menu` als AppKit-Knopf dar und übernimmt dabei
// nur Text und SF-Symbole – eigene Symbole (hier als Canvas gezeichnet) bleiben unsichtbar. Darum war z. B.
// die Sortierung in Version 1.0 nicht zu sehen. Alle Menüs mit Symbol-Beschriftung verwenden deshalb diese
// Bausteine; Kontextmenüs (Rechtsklick) bleiben nativ.

/// Zugriff auf das offene Menü (z. B. zum Schließen nach einer Auswahl).
struct GlassMenuContext {
    let close: () -> Void
}

/// Schaltfläche, die ein Glas-Menü (Popover) öffnet.
struct GlassMenuButton<Label: View, Content: View>: View {
    @Environment(\.musicColors) private var colors
    @Environment(\.glassEnabled) private var glass
    let help: String
    var arrowEdge: Edge = .bottom
    var width: CGFloat = 250
    @ViewBuilder let label: () -> Label
    @ViewBuilder let content: (GlassMenuContext) -> Content
    @State private var open = false

    init(help: String, arrowEdge: Edge = .bottom, width: CGFloat = 250,
         @ViewBuilder label: @escaping () -> Label,
         @ViewBuilder content: @escaping (GlassMenuContext) -> Content) {
        self.help = help
        self.arrowEdge = arrowEdge
        self.width = width
        self.label = label
        self.content = content
    }

    var body: some View {
        Button { open.toggle() } label: { label() }
            .buttonStyle(PressScaleStyle(scale: 0.9))
            .help(help)
            .accessibilityLabel(help)
            .popover(isPresented: $open, arrowEdge: arrowEdge) {
                GlassMenuPanel(width: width) {
                    content(GlassMenuContext(close: { open = false }))
                }
                .environment(\.musicColors, colors)
                .environment(\.glassEnabled, glass)
                .environment(\.colorScheme, colors.dark ? .dark : .light)
            }
    }
}

extension GlassMenuButton where Label == GlassMenuIconLabel {
    /// Symbol-Schaltfläche (wie `BarAction`), die ein Menü öffnet.
    init(icon: String, help: String, active: Bool = false, iconSize: CGFloat = 17, touch: CGFloat = 32,
         arrowEdge: Edge = .bottom, width: CGFloat = 250,
         @ViewBuilder content: @escaping (GlassMenuContext) -> Content) {
        self.init(help: help, arrowEdge: arrowEdge, width: width,
                  label: { GlassMenuIconLabel(icon: icon, active: active, iconSize: iconSize, touch: touch) },
                  content: content)
    }
}

/// Beschriftung einer Symbol-Menüschaltfläche (gleiches Aussehen wie `IconTap`).
struct GlassMenuIconLabel: View {
    @Environment(\.musicColors) private var colors
    @Environment(\.isEnabled) private var enabled
    let icon: String
    var active: Bool = false
    var iconSize: CGFloat = 17
    var touch: CGFloat = 32
    @State private var hover = false

    var body: some View {
        Icon(icon, size: iconSize, color: (active ? colors.accentText : colors.textPrimary).opacity(enabled ? 1 : 0.32))
            .frame(width: touch, height: touch)
            .background(Circle().fill(active ? colors.accentSoft : colors.textPrimary.opacity(hover && enabled ? 0.07 : 0)))
            .contentShape(Circle())
            .onHover { hover = $0 }
    }
}

/// Inhalt eines Glas-Menüs (auch für eigene Popover verwendbar).
struct GlassMenuPanel<Content: View>: View {
    @Environment(\.musicColors) private var colors
    var width: CGFloat = 250
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            content()
        }
        .padding(6)
        .frame(width: width, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Eine Zeile im Glas-Menü: Symbol bzw. Häkchen, Titel, optional rechts ein Wert oder Kürzel.
struct GlassMenuItem: View {
    @Environment(\.musicColors) private var colors
    @Environment(\.isEnabled) private var enabled
    let title: String
    var icon: String? = nil
    var checked: Bool = false
    var detail: String? = nil
    var destructive: Bool = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                ZStack {
                    if checked {
                        Icon(Icons.check, size: 15, color: colors.accentText)
                    } else if let icon {
                        Icon(icon, size: 15, color: destructive ? colors.danger : colors.textSecondary)
                    }
                }
                .frame(width: 18)
                Text(title)
                    .font(Typo.inter(13, checked ? .semibold : .regular))
                    .foregroundColor(destructive ? colors.danger : colors.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 10)
                if let detail {
                    Text(detail)
                        .font(Typo.inter(12, .medium))
                        .foregroundColor(colors.textTertiary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(hover && enabled ? colors.accent.opacity(colors.dark ? 0.22 : 0.13) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .opacity(enabled ? 1 : 0.4)
        .accessibilityAddTraits(checked ? .isSelected : [])
    }
}

/// Kleine Überschrift im Glas-Menü (Versalien, gedämpft).
struct GlassMenuHeader: View {
    @Environment(\.musicColors) private var colors
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(Typo.inter(10.5, .semibold))
            .tracking(0.6)
            .foregroundColor(colors.textTertiary)
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 3)
    }
}

/// Trennlinie im Glas-Menü.
struct GlassMenuDivider: View {
    @Environment(\.musicColors) private var colors

    var body: some View {
        Rectangle()
            .fill(colors.hairline)
            .frame(height: 1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
    }
}

/// Aufklappbarer Unterpunkt im Glas-Menü (statt verschachtelter Menüs).
struct GlassMenuDisclosure<Content: View>: View {
    @Environment(\.musicColors) private var colors
    let title: String
    var icon: String? = nil
    @ViewBuilder let content: () -> Content
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            GlassMenuItem(title: title, icon: icon, detail: expanded ? "▾" : "▸") {
                withAnimation(Motion.easeOut(0.18)) { expanded.toggle() }
            }
            if expanded {
                VStack(alignment: .leading, spacing: 1) { content() }
                    .padding(.leading, 14)
                    .transition(.opacity)
            }
        }
    }
}

/// Öffnet das Einstellungsfenster – auf allen unterstützten macOS-Versionen gleich (eigenes Fenster
/// statt der `Settings`-Szene, deren Öffnen per Befehl ab macOS 14 nicht mehr möglich ist).
enum SettingsWindow {
    static let id = "settings"
}
