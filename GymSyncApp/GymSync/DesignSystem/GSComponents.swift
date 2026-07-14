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
        // Collapses the icon+label VStack into a single accessibility
        // element with an exact, stable label (matches the pattern already
        // used by AppearanceView.paletteRow below) — without this, VoiceOver
        // (and XCUITest's `app.buttons["Home"]` queries, used by the
        // GymSyncScreenshots UI test target) would see the button's label as
        // some concatenation of the SF Symbol's own accessible name plus the
        // title text, which isn't a reliable exact match.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.label)
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
// Settings section (Home Gym, Apple Health Sync, etc.) and the Settings Hub
// group box (Appearance, Notifications, Home Gym, Default rest timer —
// new-canvas-section.diff's "Settings Hub" frame, Canvas Completion Task 2).
//
// `icon`/`value` are optional and default to `nil` — existing call sites
// (title + action only) are unaffected. When provided: `icon` renders an
// 18pt accent-colored SF Symbol (nearest-equivalent to the diff's raw SVGs)
// leading the title; `value` renders a trailing neutral700 preview string
// before the chevron (e.g. "Midnight", "On", "2:00").
//
// `showDivider` (default `true`) lets a caller that wraps several rows in its
// own 1px-bordered group box (per the diff's "internal dividers" spec)
// suppress the bottom divider on the last row in the group, so it doesn't
// double up against the group box's own bottom border — same technique
// `NotificationPreferencesView.groupSection` already uses for its toggle
// rows.

public struct GSSettingsRow: View {
    @Environment(\.gsTheme) private var theme

    private let title: String
    private let icon: String?
    private let value: String?
    private let showDivider: Bool
    private let action: () -> Void

    public init(
        title: String,
        icon: String? = nil,
        value: String? = nil,
        showDivider: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.value = value
        self.showDivider = showDivider
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(theme.accent)
                }
                Text(title)
                    .font(GSFont.bodyMedium(14, relativeTo: .subheadline))
                    .foregroundColor(theme.text)
                Spacer()
                if let value {
                    Text(value)
                        .font(GSFont.body(13, relativeTo: .caption))
                        .foregroundColor(theme.neutral700)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(theme.neutral500)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(theme.surface)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if showDivider {
                    Rectangle().fill(theme.divider).frame(height: 1)
                }
            }
        }
        .buttonStyle(.plain)
        // Collapses icon+title+value+chevron into one accessibility element
        // labeled by `title` alone (ignores the mutable trailing `value`,
        // e.g. the current palette name) — same idiom as
        // AppearanceView.paletteRow, and what lets the GymSyncScreenshots UI
        // test target find this row via an exact `app.buttons["Appearance"]`
        // query regardless of its current preview value.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
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

// MARK: - GSEmptyState
//
// First-run / zero-data block: a bordered icon square (64×64, 2pt divider
// border, 45%-opacity glyph) + bold headline + centered muted body copy
// (max width 250) + an optional primary CTA + an optional secondary ghost
// link. Matches the canvas "No crew yet" frame (Canvas Completion Task 4,
// proof p30-empty-offline; markup `docs/design/Gym Sync App
// Designs.dc.html` lines ~2279-2288).
//
// Deliberately does NOT force full-screen vertical centering — the canvas
// frame shows this as the SOLE content of an isolated "states" mockup, but
// real call sites (SocialTabView's Groups section, FriendsView's Friends
// section) sit alongside other content, so this renders as a self-contained
// block wherever the empty condition already lives, matching how the
// pre-existing plain-text empties it replaces were positioned.
//
// The CTA button intentionally has no `.frame(maxWidth: .infinity)` — left
// unconstrained, `GSPrimaryButtonStyle`'s internal `Spacer` collapses to
// zero width, so the button hugs its label exactly like the canvas's
// `justify-content:center` override, and the enclosing VStack's default
// `.center` alignment centers the whole content-sized button. Same trick
// for the secondary ghost link.

public struct GSEmptyState: View {
    @Environment(\.gsTheme) private var theme

    private let icon: String
    private let title: String
    private let message: String
    private let ctaTitle: String?
    private let action: (() -> Void)?
    private let secondaryTitle: String?
    private let secondaryAction: (() -> Void)?

    public init(
        icon: String,
        title: String,
        message: String,
        ctaTitle: String? = nil,
        action: (() -> Void)? = nil,
        secondaryTitle: String? = nil,
        secondaryAction: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.ctaTitle = ctaTitle
        self.action = action
        self.secondaryTitle = secondaryTitle
        self.secondaryAction = secondaryAction
    }

    public var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Rectangle().strokeBorder(theme.divider, lineWidth: 2)
                Image(systemName: icon)
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(theme.text.opacity(0.45))
            }
            .frame(width: 64, height: 64)
            .padding(.bottom, 18)

            Text(title)
                .font(GSFont.heading(22, relativeTo: .title2))
                .foregroundStyle(theme.text)

            Text(message)
                .font(GSFont.body(14, relativeTo: .subheadline))
                .foregroundStyle(theme.neutral500)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 250)
                .padding(.top, 6)

            if let ctaTitle, let action {
                Button(ctaTitle, action: action)
                    .buttonStyle(GSPrimaryButtonStyle(fontSize: 14, verticalPadding: 12))
                    .padding(.top, 18)
            }

            if let secondaryTitle, let secondaryAction {
                Button(secondaryTitle, action: secondaryAction)
                    .buttonStyle(GSGhostButtonStyle())
                    .padding(.top, 8)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - GSErrorCard
//
// Blank-list-plus-failure block: same visual language as `GSEmptyState` but
// at the canvas's smaller "Couldn't load the roster" scale (56×56 icon
// square, 20pt title, 13pt/240pt-wide message, single "Try again" CTA — no
// secondary link). Matches proof p31-errors; markup lines ~2318-2326.
//
// Contract (Canvas Completion Task 4): this card is for the "list would
// otherwise be blank AND a load failed" case only — best-effort refresh
// failures that leave stale data on screen stay silent (no card), so a
// transient network blip never converts non-blocking semantics into a
// blocking error. Callers are expected to gate this behind their own
// `<list>.isEmpty && <lastLoadFailed>` check; it does not gate itself.

public struct GSErrorCard: View {
    @Environment(\.gsTheme) private var theme

    private let title: String
    private let message: String
    private let retryTitle: String
    private let retry: () -> Void

    public init(
        title: String = "Couldn't load",
        message: String,
        retryTitle: String = "Try again",
        retry: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.retryTitle = retryTitle
        self.retry = retry
    }

    public var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Rectangle().strokeBorder(theme.divider, lineWidth: 2)
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(theme.text.opacity(0.45))
            }
            .frame(width: 56, height: 56)
            .padding(.bottom, 14)

            Text(title)
                .font(GSFont.heading(20, relativeTo: .title3))
                .foregroundStyle(theme.text)

            Text(message)
                .font(GSFont.body(13, relativeTo: .footnote))
                .foregroundStyle(theme.neutral500)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 240)
                .padding(.top, 6)

            Button(retryTitle, action: retry)
                .buttonStyle(GSPrimaryButtonStyle(fontSize: 14, verticalPadding: 11))
                .padding(.top, 16)
        }
        .multilineTextAlignment(.center)
        .padding(16)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - GSOfflineBanner
//
// "Reconnecting…" pill — 1px divider border, surface fill, a pulsing accent
// dot, bold "Reconnecting…" label, trailing muted "Showing your last synced
// data" caption. Matches proof p30-empty-offline; markup lines ~2272-2277.
//
// The dot is a `Circle` (not the app's usual zero-radius `Rectangle`) —
// this is a deliberate, recurring exception in the canvas markup for
// "live activity blip" indicators specifically (the same round dot appears
// on the chat typing indicator and voice-recording composer; contrast the
// SQUARE "LIVE" session badge dot elsewhere in the same file), not an
// oversight of the house zero-radius rule.
//
// Driven by `ConnectivityMonitor.shared.isOnline` — this view itself has no
// opinion on when to show; callers gate it (`if !connectivity.isOnline`).

public struct GSOfflineBanner: View {
    @Environment(\.gsTheme) private var theme
    @State private var isDimmed = false

    public init() {}

    public var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(theme.accent)
                .frame(width: 8, height: 8)
                .opacity(isDimmed ? 0.25 : 1)

            Text("Reconnecting…")
                .font(GSFont.bold(12, relativeTo: .caption))
                .foregroundStyle(theme.text)

            Spacer(minLength: 8)

            Text("Showing your last synced data")
                .font(GSFont.body(11, relativeTo: .caption2))
                .foregroundStyle(theme.neutral500)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(theme.surface)
        .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))
        .onAppear {
            // Canvas Completion Task 4 fix round 1: `repeatForever(autoreverses:
            // true)` doubles a single-leg duration into a full forward+reverse
            // cycle — `duration: 1` here was actually a 2s cycle, not the
            // markup's `animation:gsPulse 1s ease-in-out infinite` (1s full
            // cycle). Halved to 0.5s per leg so the autoreversed round trip
            // matches the spec's 1s cycle.
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                isDimmed = true
            }
        }
    }
}

// MARK: - GSInlineErrorBanner
//
// Solid-accent inline error banner — bold lead-in + continuation copy, single
// "Try again" CTA. Matches proof p31-errors' "Set didn't save" toast shape
// (markup lines ~2313-2317: accent fill, bg-colored text, exclamation-circle
// icon, single flowing message) with ONE deliberate, behavior-truthful
// deviation from the literal proof copy and shape:
//
// - The proof's copy is "Set didn't save. We'll retry when you're back
//   online." — this app has no offline retry queue (no outbox, no background
//   sync), so that copy would promise a capability that doesn't exist.
//   Callers should pass a `message` that's honest about there being no
//   auto-retry (e.g. "Check your connection, then try again").
// - The proof's banner has no button at all (it relies on the fabricated
//   auto-retry). This component adds a real "Try again" CTA so the failure
//   is actually recoverable — callers wire `retry` to re-invoke the exact
//   action that failed.
//
// See Canvas Completion Task 4 fix round 1 report for the full record of
// this deviation.

public struct GSInlineErrorBanner: View {
    @Environment(\.gsTheme) private var theme

    private let title: String
    private let message: String
    private let retryTitle: String
    private let retry: () -> Void

    public init(
        title: String,
        message: String,
        retryTitle: String = "Try again",
        retry: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.retryTitle = retryTitle
        self.retry = retry
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(theme.bg)

            VStack(alignment: .leading, spacing: 8) {
                (
                    Text(title).font(GSFont.bold(13, relativeTo: .footnote))
                    + Text(" \(message)").font(GSFont.body(13, relativeTo: .footnote))
                )
                .foregroundStyle(theme.bg)
                .fixedSize(horizontal: false, vertical: true)

                Button(action: retry) {
                    Text(retryTitle)
                        .font(GSFont.bold(12, relativeTo: .caption))
                        .foregroundStyle(theme.bg)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .overlay(Rectangle().strokeBorder(theme.bg.opacity(0.6), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(theme.accent)
    }
}
