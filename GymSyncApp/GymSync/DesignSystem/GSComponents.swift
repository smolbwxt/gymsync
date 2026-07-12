import SwiftUI

// MARK: - GSPrimaryButtonStyle
//
// Solid accent fill, zero corner radius, flush-left label.
// Pressed state shifts to accent600 (darker tint).
// Use `.frame(maxWidth: .infinity)` on the button to make it full-width.

public struct GSPrimaryButtonStyle: ButtonStyle {
    @Environment(\.gsTheme) private var theme

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 0) {
            configuration.label
            Spacer(minLength: 0)
        }
        .font(GSFont.bold(16, relativeTo: .body))
        .foregroundColor(configuration.isPressed ? theme.neutral100 : theme.bg)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(configuration.isPressed ? theme.accent600 : theme.accent)
        .cornerRadius(0)
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - GSSecondaryButtonStyle
//
// 1px accent border, transparent fill, flush-left label.
// Pressed state: accent100 fill tint + accent600 border.

public struct GSSecondaryButtonStyle: ButtonStyle {
    @Environment(\.gsTheme) private var theme

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 0) {
            configuration.label
            Spacer(minLength: 0)
        }
        .font(GSFont.bold(16, relativeTo: .body))
        .foregroundColor(configuration.isPressed ? theme.accent600 : theme.accent)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(configuration.isPressed ? theme.accent100 : Color.clear)
        .cornerRadius(0)
        .overlay(
            Rectangle()
                .strokeBorder(
                    configuration.isPressed ? theme.accent600 : theme.accent,
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - GSGhostButtonStyle
//
// No fill, no border — text-only. Flush-left label.
// Pressed state: neutral100 fill tint + accent700 label colour.

public struct GSGhostButtonStyle: ButtonStyle {
    @Environment(\.gsTheme) private var theme

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 0) {
            configuration.label
            Spacer(minLength: 0)
        }
        .font(GSFont.bodyMedium(16, relativeTo: .body))
        .foregroundColor(configuration.isPressed ? theme.accent700 : theme.accent)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(configuration.isPressed ? theme.neutral100 : Color.clear)
        .cornerRadius(0)
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - GSCard
//
// Surface-filled content card, zero corner radius.
// Optional 1 pt neutral300 border via `bordered` parameter.

public struct GSCard<Content: View>: View {
    @Environment(\.gsTheme) private var theme

    private let bordered: Bool
    private let content: Content

    public init(bordered: Bool = false, @ViewBuilder content: () -> Content) {
        self.bordered = bordered
        self.content = content()
    }

    public var body: some View {
        content
            .background(theme.surface)
            .cornerRadius(0)
            .overlay(
                bordered
                    ? Rectangle().strokeBorder(theme.neutral300, lineWidth: 1)
                    : nil
            )
    }
}

// MARK: - GSTag

public enum GSTagStyle {
    case accent   // accent100 fill, accent text
    case neutral  // neutral300 fill, neutral700 text
    case outline  // transparent fill, neutral400 border, neutral700 text
}

public struct GSTag: View {
    @Environment(\.gsTheme) private var theme

    private let text: String
    private let style: GSTagStyle

    public init(text: String, style: GSTagStyle = .neutral) {
        self.text = text
        self.style = style
    }

    public var body: some View {
        Text(text)
            .font(GSFont.bodyMedium(12, relativeTo: .caption))
            .foregroundColor(foregroundColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor)
            .cornerRadius(0)
            .overlay(
                style == .outline
                    ? Rectangle().strokeBorder(theme.neutral400, lineWidth: 1)
                    : nil
            )
    }

    private var foregroundColor: Color {
        switch style {
        case .accent:   return theme.accent
        case .neutral:  return theme.neutral700
        case .outline:  return theme.neutral700
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .accent:   return theme.accent100
        case .neutral:  return theme.neutral300
        case .outline:  return Color.clear
        }
    }
}

// MARK: - GSDivider
//
// Strong 2 pt horizontal rule in the theme divider colour.
// Replaces SwiftUI's default hairline Divider throughout the app.

public struct GSDivider: View {
    @Environment(\.gsTheme) private var theme

    public init() {}

    public var body: some View {
        theme.divider
            .frame(height: 2)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - GSTabBar
//
// Custom bottom tab dock replacing system TabView chrome (DEFECT-9).
// theme.bg background, 2pt top border (theme.divider), 5 equal-flex items.
// Outline SF Symbols (no `.fill`), 21pt icon, 10pt GSFont.bold label.
// Active = theme.accent, inactive = theme.text.opacity(0.45).
// Matches canvas dock spec verbatim (Dossier §A.5).

public struct GSTabBar: View {
    @Environment(\.gsTheme) private var theme

    @Binding private var selection: AppState.Tab

    public init(selection: Binding<AppState.Tab>) {
        self._selection = selection
    }

    private struct Item {
        let tab: AppState.Tab
        let icon: String
        let label: String
    }

    private let items: [Item] = [
        Item(tab: .home, icon: "house", label: "Home"),
        Item(tab: .library, icon: "book", label: "Library"),
        Item(tab: .social, icon: "person.2", label: "Social"),
        Item(tab: .stats, icon: "chart.bar", label: "Stats"),
        Item(tab: .you, icon: "person.crop.circle", label: "You"),
    ]

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.tab) { item in
                tabButton(item)
            }
        }
        .padding(.top, 8)
        .background(theme.bg)
        .overlay(alignment: .top) {
            theme.divider
                .frame(height: 2)
        }
    }

    @ViewBuilder
    private func tabButton(_ item: Item) -> some View {
        let isActive = selection == item.tab
        Button {
            selection = item.tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: item.icon)
                    .font(.system(size: 21, weight: .regular))
                Text(item.label)
                    .font(GSFont.bold(10, relativeTo: .caption2))
            }
            .foregroundColor(isActive ? theme.accent : theme.text.opacity(0.45))
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - GSSectionHeader
//
// Uppercase, tracked kicker label — neutral700 text.
// Appears above grouped content sections (matches canvas kicker treatment).

public struct GSSectionHeader: View {
    @Environment(\.gsTheme) private var theme

    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text.uppercased())
            .font(GSFont.bodyMedium(11, relativeTo: .caption2))
            .tracking(1.2)
            .foregroundColor(theme.neutral700)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
