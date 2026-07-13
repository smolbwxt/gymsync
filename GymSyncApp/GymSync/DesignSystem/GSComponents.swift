import SwiftUI
import Charts

// MARK: - GSPrimaryButtonStyle
//
// Solid accent fill, zero corner radius, flush-left label.
// Pressed state shifts to accent600 (darker tint).
// Use `.frame(maxWidth: .infinity)` on the button to make it full-width.

public struct GSPrimaryButtonStyle: ButtonStyle {
    @Environment(\.gsTheme) private var theme

    private let fontSize: CGFloat
    private let verticalPadding: CGFloat

    /// `fontSize`/`verticalPadding` default to the canonical 16pt/12pt treatment;
    /// callers matching a canvas spec with a different scale (e.g. Home's
    /// "Start Solo Workout" CTA at 15pt/14pt) can override per-instance.
    public init(fontSize: CGFloat = 16, verticalPadding: CGFloat = 12) {
        self.fontSize = fontSize
        self.verticalPadding = verticalPadding
    }

    public func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 0) {
            configuration.label
            Spacer(minLength: 0)
        }
        .font(GSFont.bold(fontSize, relativeTo: .body))
        .foregroundColor(configuration.isPressed ? theme.neutral100 : theme.bg)
        .padding(.horizontal, 16)
        .padding(.vertical, verticalPadding)
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

    private let fontSize: CGFloat
    private let horizontalPadding: CGFloat
    private let verticalPadding: CGFloat

    /// Defaults match the canonical 16pt/16-horizontal/12-vertical treatment;
    /// callers matching a canvas spec with a smaller scale (e.g. a compact
    /// "Open" action inside a denied-permission banner) can override
    /// per-instance — mirrors `GSPrimaryButtonStyle`'s existing pattern.
    public init(fontSize: CGFloat = 16, horizontalPadding: CGFloat = 16, verticalPadding: CGFloat = 12) {
        self.fontSize = fontSize
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
    }

    public func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 0) {
            configuration.label
            Spacer(minLength: 0)
        }
        .font(GSFont.bold(fontSize, relativeTo: .body))
        .foregroundColor(configuration.isPressed ? theme.accent600 : theme.accent)
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
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
    private let backgroundColor: Color?
    private let content: Content

    /// `backgroundColor` defaults to `theme.surface`; pass an override (e.g.
    /// `theme.accent100` for a PR-celebration card) for non-default fills.
    public init(bordered: Bool = false, backgroundColor: Color? = nil, @ViewBuilder content: () -> Content) {
        self.bordered = bordered
        self.backgroundColor = backgroundColor
        self.content = content()
    }

    public var body: some View {
        content
            .background(backgroundColor ?? theme.surface)
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

    // Not `public`: AppState.Tab is an internal type (AppState itself is
    // implicitly internal), so a public initializer referencing it would be
    // an access-level violation. GSTabBar is only constructed from RootView
    // within this single-target app, so internal init access is sufficient.
    init(selection: Binding<AppState.Tab>) {
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

// MARK: - GSHidesDock
//
// PreferenceKey + convenience modifier for hiding the custom bottom dock
// (`GSTabBar`) while a pushed detail screen is on-screen (DEFECT-1 fix).
//
// `.safeAreaInset` (used by `GSTabBar`'s host) only augments the safe area
// for its own SwiftUI-layout descendants — a `NavigationStack`'s pushed
// `navigationDestination` content is presented via UIKit's push-transition
// machinery and never sees that inset, so the dock draws over bottom-pinned
// UI on pushed screens (action bars, input bars, sticky CTAs). Preferences,
// unlike safe-area insets, DO propagate up through pushed destination
// content to ancestors above the `NavigationStack` (they travel through the
// SwiftUI view graph, not the UIKit presentation layer), so this preference
// reaches `MainTabView` correctly and it can omit the dock entirely for the
// duration — mirroring system `hidesBottomBarWhenPushed` behavior instead of
// trying to make `safeAreaInset` reach through the push boundary.
public struct GSHidesDock: PreferenceKey {
    public static let defaultValue: Bool = false
    public static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

extension View {
    /// Marks this screen as one that should hide the app's custom bottom
    /// dock (`GSTabBar`) while it is part of the visible navigation stack.
    /// Apply to pushed `navigationDestination` content with bottom-pinned UI
    /// of its own (action bars, input bars, sticky CTAs) — NOT to tab ROOT
    /// views, which must keep the dock visible.
    public func gsHidesDock(_ hides: Bool = true) -> some View {
        preference(key: GSHidesDock.self, value: hides)
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

// MARK: - GSSettingsRow
//
// Full-width tappable settings row: flush-left title + trailing chevron.
// ≥44pt tap target via vertical padding, contentShape for edge-to-edge hit
// testing, 1px divider along the bottom edge. Used by the You tab's
// Settings section (Home Gym, Apple Health Sync, etc.).

public struct GSSettingsRow: View {
    @Environment(\.gsTheme) private var theme

    private let title: String
    private let action: () -> Void

    public init(title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(GSFont.bodyMedium(14, relativeTo: .subheadline))
                    .foregroundColor(theme.text)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(theme.neutral500)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(theme.surface)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle().fill(theme.divider).frame(height: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - GSSecondarySignOutButtonStyle
//
// Sign-Out variant of GSSecondaryButtonStyle: accent700 text (vs accent),
// neutral300 border (vs accent), CENTERED label (canvas exception to the
// DS system's flush-left rule — canvas explicitly sets
// `justify-content:center` for the You-tab Sign Out button only).
// Promoted from a private one-off in YouTabView so it's reusable/testable.

public struct GSSecondarySignOutButtonStyle: ButtonStyle {
    @Environment(\.gsTheme) private var theme

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            configuration.label
            Spacer(minLength: 0)
        }
        .font(GSFont.bold(16, relativeTo: .body))
        .foregroundColor(configuration.isPressed ? theme.accent600 : theme.accent700)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(configuration.isPressed ? theme.accent100 : Color.clear)
        .cornerRadius(0)
        .overlay(
            Rectangle()
                .strokeBorder(
                    configuration.isPressed ? theme.accent600 : theme.neutral300,
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - GSStatTile
//
// Compact surface-card metric tile: bold value + muted label.
// Sized to sit flex:1 in a row (Home stat row, You-tab stat row, etc.).
// `valueColor` lets callers accent a particular tile's value (e.g. accent700
// for "PRs this month") while leaving the label at the standard neutral700.

public struct GSStatTile: View {
    @Environment(\.gsTheme) private var theme

    private let value: String
    private let label: String
    private let valueColor: Color?
    private let valueFontSize: CGFloat
    private let labelColor: Color?
    private let uppercaseLabel: Bool

    /// `valueFontSize` defaults to the canonical 20pt (Home tab tiles); callers
    /// matching a canvas spec with a smaller scale (e.g. You tab's 18pt stat
    /// tiles) can override per-instance.
    ///
    /// `labelColor`/`uppercaseLabel` default to the original neutral700,
    /// sentence-case look — opt in per-instance (e.g. Exercise History's
    /// tracked, accent-colored, all-caps tile labels) without touching any
    /// other call site.
    public init(
        value: String,
        label: String,
        valueColor: Color? = nil,
        valueFontSize: CGFloat = 20,
        labelColor: Color? = nil,
        uppercaseLabel: Bool = false
    ) {
        self.value = value
        self.label = label
        self.valueColor = valueColor
        self.valueFontSize = valueFontSize
        self.labelColor = labelColor
        self.uppercaseLabel = uppercaseLabel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(GSFont.bold(valueFontSize, relativeTo: .title3))
                .foregroundColor(valueColor ?? theme.text)
            Text(uppercaseLabel ? label.uppercased() : label)
                .font(GSFont.body(10, relativeTo: .caption2))
                .tracking(uppercaseLabel ? 1.2 : 0)
                .foregroundColor(labelColor ?? theme.neutral700)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface)
        .cornerRadius(0)
    }
}

// MARK: - GSMiniTrendCard
//
// Compact sparkline trend card: uppercase tracked kicker + optional delta
// badge header, axis-free line chart body. Companion to `TrendChartView`
// (which adds axis labels + an 8w/6m/1y range toggle for the full Exercise
// History screen) — this variant is for smaller inline placements, like
// Exercise Detail's "Est. 1RM · 12 weeks" trend card.

public struct GSMiniTrendCard: View {
    @Environment(\.gsTheme) private var theme

    private let kicker: String
    private let data: [(Date, Double)]
    private let deltaText: String?

    public init(kicker: String, data: [(Date, Double)], deltaText: String? = nil) {
        self.kicker = kicker
        self.data = data
        self.deltaText = deltaText
    }

    public var body: some View {
        GSCard(bordered: true) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(kicker.uppercased())
                        .font(GSFont.bodyMedium(10, relativeTo: .caption2))
                        .tracking(1.0)
                        .foregroundColor(theme.neutral700)
                    Spacer()
                    if let deltaText {
                        Text(deltaText)
                            .font(GSFont.body(12, relativeTo: .caption))
                            .foregroundColor(theme.accent700)
                    }
                }
                if data.isEmpty {
                    Text("Not enough data yet.")
                        .font(GSFont.body(13, relativeTo: .caption))
                        .foregroundColor(theme.neutral500)
                } else {
                    Chart(Array(data.enumerated()), id: \.offset) { _, point in
                        LineMark(x: .value("Date", point.0), y: .value("Value", point.1))
                            .foregroundStyle(theme.accent)
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .frame(height: 90)
                }
            }
            .padding(16)
        }
    }
}

// MARK: - GSSquareToggleStyle
//
// ToggleStyle rendering the square on/off knob (46x27 track, 21x21 knob,
// 3pt inset). On: accent track, bg-colored knob, knob right-aligned.
// Off: neutral300 track, neutral500 knob, knob left-aligned.
// Drawn control stays exactly 46x27; the tappable hit area expands to >=44pt
// via `.frame(minWidth:minHeight:)`.

public struct GSSquareToggleStyle: ToggleStyle {
    @Environment(\.gsTheme) private var theme

    public func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Rectangle()
                    .fill(configuration.isOn ? theme.accent : theme.neutral300)
                    .frame(width: 46, height: 27)
                Rectangle()
                    .fill(configuration.isOn ? theme.bg : theme.neutral500)
                    .frame(width: 21, height: 21)
                    .padding(3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .animation(.easeInOut(duration: 0.15), value: configuration.isOn)
    }
}

// MARK: - GSToggle
//
// Custom square on/off control replacing SwiftUI's system `Toggle` (canvas
// redraw, Notif Preferences frame — see new-canvas-section.diff). 46x27
// track, 21x21 knob, knob inset 3pt (vertical centering falls out of
// 27-21=6 symmetric padding). On: accent track, bg-colored knob, knob
// right-aligned. Off: neutral300 track, neutral500 knob, knob left-aligned.
// Per Designer ruling #1 ("small drawn boxes, 44pt invisible hit areas"),
// the drawn track stays exactly 46x27 — only the tappable region is padded
// out to >=44pt via `.frame(minWidth:minHeight:)`, same pattern used by
// GSSettingsRow/GSPrimaryButtonStyle elsewhere in this file.
//
// Internally uses a real SwiftUI `Toggle` + `GSSquareToggleStyle`, which
// provides proper VoiceOver semantics (switch trait, on/off value). Optional
// `label` param (defaulted nil for backward compatibility) applies
// accessibility label when present.
//
// Label rendering (including the "60% opacity when off" treatment) is the
// caller's responsibility — this view is a pure `Bool` control with no
// visual label of its own, matching the canvas markup where the label is a
// sibling `<span>`, not part of the toggle itself.

public struct GSToggle: View {
    @Binding private var isOn: Bool
    private let label: String?

    /// Creates a GSToggle with optional accessibility label. Public API remains
    /// identical to the prior Button-based implementation — callers unchanged.
    /// Optional `label` param (defaulted nil) applies accessibilityLabel when
    /// present, e.g., GSToggle(isOn: $prefs["foo"], label: "Notifications").
    public init(isOn: Binding<Bool>, label: String? = nil) {
        self._isOn = isOn
        self.label = label
    }

    public var body: some View {
        Toggle(isOn: $isOn) {
            EmptyView()
        }
        .labelsHidden()
        .toggleStyle(GSSquareToggleStyle())
        .accessibilityLabel(label ?? "")
    }
}
