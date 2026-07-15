import SwiftUI
import Charts
import UIKit

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
// Matches the design system's `.btn-secondary` (verified against the rendered
// canvas component sheet): a 1px DIVIDER-gray border with TEXT-color label —
// a quiet outline that recedes on the surface, NOT the accent. Earlier this
// drew border + label in `theme.accent`, which read as a prominent navy
// rectangle everywhere it was used (the You-tab "Edit" button et al).
// Pressed state: a faint text-tint fill, per the DS hover/active treatment.

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
        .foregroundColor(theme.text)
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(configuration.isPressed ? theme.text.opacity(0.08) : Color.clear)
        .cornerRadius(0)
        .overlay(
            Rectangle().strokeBorder(theme.divider, lineWidth: 1)
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
        // No accessibility flattening here: the Button's derived label is
        // "{title}, {value}" (e.g. "Appearance, Ink"), which is the right
        // VoiceOver experience — the row announces its current value. UI
        // tests must match with a BEGINSWITH predicate, not an exact label.
        // (An .accessibilityElement(children:.ignore) wrapper was tried and
        // reverted: applied outside a Button it adds a non-interactive Other
        // element AROUND the button instead of relabeling it — CI run
        // 29298949155's hierarchy dump has the evidence.)
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

// MARK: - GSTalkingBars
//
// Small animated 3-bar level meter — canvas's `gsTalk .9s ease-in-out
// infinite` staggered treatment (Dossier §A.2 lobby "talking" roster state +
// PTT "Transmitting" trailing meter). Purely decorative — not driven by live
// audio levels (`VoiceRoomService` exposes no metering API), same honesty
// note as `ChatView.RecordingWaveformView`, which this mirrors.

struct GSTalkingBars: View {
    let color: Color
    var barWidth: CGFloat = 3
    var maxHeight: CGFloat = 14

    @State private var animate = false

    private static let heightScales: [CGFloat] = [0.5, 1.0, 0.7]

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(Self.heightScales.enumerated()), id: \.offset) { index, scale in
                Capsule()
                    .fill(color)
                    .frame(width: barWidth, height: animate ? maxHeight * scale : maxHeight * scale * 0.35)
                    .animation(
                        .easeInOut(duration: 0.45)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.3),
                        value: animate
                    )
            }
        }
        .frame(height: maxHeight)
        .onAppear { animate = true }
    }
}

// MARK: - GSConnectingVoicePill
//
// "Connecting voice…" header pill — pulsing accent dot + bold label, 1px
// divider border (Dossier §A.2: the lobby header and the live-session header
// both show this identical pill while `VoiceRoomService.state == .connecting`).
// Same contract as `GSOfflineBanner` above: this view has no opinion on when
// to show — callers gate visibility (`if case .connecting = ...`).

struct GSConnectingVoicePill: View {
    @Environment(\.gsTheme) private var theme
    @State private var isDimmed = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(theme.accent)
                .frame(width: 7, height: 7)
                .opacity(isDimmed ? 0.35 : 1)
            Text("Connecting voice…")
                .font(GSFont.bold(11, relativeTo: .caption2))
                .foregroundStyle(theme.text)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                isDimmed = true
            }
        }
    }
}

// MARK: - GSVoiceUnavailableBanner
//
// Degraded-voice banner — accent left-border card, mic-slash icon, "Voice
// unavailable" title + message, secondary "Retry" button (Dossier §A.2's
// lobby "Voice unavailable / Couldn't join the room" frame + the live-session
// dock's "persistent card elev-sm degraded banner"). No shipped precedent
// existed for this exact shape (grepped the codebase — nothing named
// voice-unavailable/GSErrorCard-adjacent matched it), so this is a fresh,
// small component rather than a reuse; `GSErrorCard` above was considered
// but its centered-icon-square layout doesn't match the canvas's inline
// left-border card, so it wasn't retrofit here.

struct GSVoiceUnavailableBanner: View {
    @Environment(\.gsTheme) private var theme

    let message: String
    let retry: () -> Void

    init(message: String = "Couldn't join the room. Text and soundboard still work.",
         retry: @escaping () -> Void) {
        self.message = message
        self.retry = retry
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "mic.slash")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(theme.accent)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text("Voice unavailable")
                    .font(GSFont.bold(14, relativeTo: .headline))
                    .foregroundStyle(theme.text)
                Text(message)
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
            }

            Spacer(minLength: 8)

            Button("Retry", action: retry)
                .buttonStyle(GSSecondaryButtonStyle(fontSize: 13, horizontalPadding: 12, verticalPadding: 8))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(theme.surface)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(theme.accent)
                .frame(width: 3)
        }
        .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))
    }
}

// MARK: - GSExpandingRing
//
// One expanding, fading circular stroke — the blessed frames' `gsRing` motif
// (`docs/design/sections/2026-07-live-voice.dc.html:24`: scale 0.7 -> 1.6,
// opacity .6 -> 0, 1.4s ease-out, infinite, non-reversing). Rendered behind
// the round PTT mic while the mic is open or held; the held state layers two
// of these with the frame's exact 0.7s stagger. Deliberately draws OUTSIDE
// its nominal frame (scaleEffect > 1) — ZStack doesn't clip, matching the
// frames where the rings overflow the 80px button freely.

struct GSExpandingRing: View {
    let color: Color
    var delay: Double = 0

    @State private var animate = false

    var body: some View {
        Circle()
            .stroke(color, lineWidth: 2)
            .scaleEffect(animate ? 1.6 : 0.7)
            .opacity(animate ? 0 : 0.6)
            .animation(
                .easeOut(duration: 1.4)
                    .repeatForever(autoreverses: false)
                    .delay(delay),
                value: animate
            )
            .onAppear { animate = true }
    }
}

// MARK: - PTTDockRow
//
// Shared live-voice push-to-talk dock control for LobbyView +
// GroupSessionLiveView. Fully self-contained — reads/drives
// `VoiceRoomService.shared` directly, no parameters needed (mirrors
// `GSTabBar`'s note above: `VoiceRoomState`/`TransmitState` are internal
// types, so this type and its properties are deliberately NOT `public`, same
// access-level reasoning).
//
// SHAPE (blessed frames, 2026-07-14 review round — these override the older
// canvas's merged rectangular row): a round 44pt mic BUTTON beside a
// SEPARATE bordered status bar (`docs/design/sections/2026-07-curation.dc.html`
// frame 1's dock row + the coach-mark frame in `2026-07-live-voice.dc.html`).
// Per state:
//   .idle / .connected(.muted)  -> secondary-style round mic (accent stroke,
//       accent glyph) + bar "Tap to talk · hold to talk live"
//   .connected(.transmitting), toggled open -> accent-FILLED round mic + one
//       gsRing + bar "MIC OPEN · TAP TO MUTE" over sub-caption "Tap toggles ·
//       press-and-hold for walkie-talkie" (live-voice frame 2)
//   .connected(.transmitting), held -> accent-filled round mic + TWO gsRings
//       (0.7s stagger) + bar "HOLDING · {elapsed} — RELEASE TO STOP" with a
//       LIVE elapsed timer (live-voice frame 1; timer is UI-side only —
//       Text(timerInterval:), zero service-side timers)
//   .connecting -> dimmed secondary mic + spinner bar "Connecting voice…"
//   .unavailable -> dashed muted mic + muted bar (pairs with
//       `GSVoiceUnavailableBanner`, shown by the caller above the dock)
//   .micDenied -> the whole row is a single full-width open-Settings button
//       (unchanged from the earlier canvas live-dock frame; the blessed
//       frames don't redraw denied)
//
// OPEN-vs-HELD is DERIVED, not stored: `.connected(.transmitting)` renders
// the holding UI iff `isHeldTransmitOwnedByThisPress` (this press began and
// owns the walkie-talkie transmission) and the open UI otherwise. A fresh
// view instance (e.g. Lobby -> live-session push, where the room connection
// deliberately survives) therefore correctly shows "MIC OPEN · TAP TO MUTE"
// for a transmission it didn't start — the only way to be transmitting with
// no finger down is hands-free.
//
// GESTURE (Task 4 AMENDMENT, 2026-07-14 — overrides the brief's hold-only
// text): the mic supports BOTH tap-to-toggle (mic stays open hands-free
// until tapped again) and hold-to-talk (walkie-talkie; release ALWAYS mutes
// a HELD transmission, never a toggled-open one). Built on
// `onLongPressGesture(minimumDuration:pressing:perform:)` — the same
// primitive ChatView's `micButton` (Task 3c) uses — with `minimumDuration`
// as the tap/hold cutoff: `perform` fires exactly when a press crosses the
// hold threshold while still down; `pressing(false)` fires on EVERY release
// regardless of whether `perform` ever fired.

struct PTTDockRow: View {
    @Environment(\.gsTheme) private var theme

    /// Monotonic per-press identity. Bumped on every press-down; captured by
    /// the threshold handler and the release handler, and re-checked before
    /// any of them consumes or clears the shared per-press state below.
    /// Without it, the shared state is corrupted by OVERLAPPING press
    /// cycles (review round 1, Important 1): hold #1 released right at the
    /// threshold parks its release Task on the in-flight `beginTransmit()`;
    /// the user immediately holds again; press #1's stale release then used
    /// to nil press #2's `holdBeginTask` reference and consume its flags —
    /// leaving press #2's release with nothing to await and nothing to end:
    /// mic stranded open. Now every deferred continuation guards on
    /// `capturedGen == pressGeneration` and simply stands down when a newer
    /// press owns the state.
    @State private var pressGeneration = 0

    /// True from the moment THIS press crosses the hold threshold (`perform`
    /// fired) until the next press-down resets it — regardless of whether
    /// that threshold-crossing actually started a transmission. Needed to
    /// tell "a genuine tap" apart from "a hold that started while the mic
    /// was already toggled open" on release — both leave
    /// `isHeldTransmitOwnedByThisPress` false, but only the former should
    /// fall through to tap-toggle (see `handleRelease`).
    @State private var holdThresholdCrossedThisPress = false

    /// True while a press owns a live walkie-talkie transmission (the hold
    /// threshold fired AND `beginTransmit()`/adoption actually took effect).
    /// Doubles as the open-vs-held display discriminator (see the type doc
    /// comment). Only when this is true does release call `endTransmit()` —
    /// a hold that starts while the mic is ALREADY tap-toggled open must
    /// never mute it on release (amendment: "a tap-toggled-open mic is never
    /// auto-muted by release").
    @State private var isHeldTransmitOwnedByThisPress = false

    /// When the current held transmission started — feeds the holding bar's
    /// live elapsed timer (`Text(timerInterval:)`, UI-side only). Set exactly
    /// when ownership is claimed, cleared exactly when it's released/reset.
    @State private var heldStartedAt: Date?

    /// The in-flight `beginTransmit()` attempt kicked off by the current
    /// press's hold-threshold crossing, if any. `handleRelease` captures this
    /// into a press-local `let` and awaits it before deciding what release
    /// means — without the await, a hold released a few ms after crossing
    /// the threshold could read `isHeldTransmitOwnedByThisPress` before the
    /// begin-transmit Task finished setting it and strand the mic open. The
    /// shared slot itself is only nil'd behind a generation check, so a
    /// stale release can never drop a newer press's task reference.
    @State private var holdBeginTask: Task<Void, Never>?

    /// True while the mic is open via TAP (hands-free, sustained). Used ONLY
    /// by the gesture logic (to protect a toggled-open mic from hold
    /// adoption/muting) — the DISPLAYED open-vs-held choice is derived from
    /// `isHeldTransmitOwnedByThisPress` instead, so a fresh view instance
    /// renders a carried-over open mic correctly even though this flag
    /// resets (review round 1, minor (b)).
    @State private var isToggledOpen = false

    private static let holdThreshold: TimeInterval = 0.35

    private var voice: VoiceRoomService { .shared }

    var body: some View {
        VStack(spacing: 0) {
            GSDivider()
            Group {
                switch voice.state {
                case .micDenied:
                    deniedRow
                case .unavailable:
                    micAndBar(mic: { unavailableMic }, bar: { unavailableBar })
                case .connecting:
                    micAndBar(mic: { connectingMic }, bar: { connectingBar })
                        .opacity(0.75)
                case .idle, .connected:
                    interactiveRow
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
        .background(theme.bg)
    }

    private var isTransmitting: Bool {
        if case .connected(.transmitting) = voice.state { return true }
        return false
    }

    private var pressGesture: PTTPressGesture {
        PTTPressGesture(threshold: Self.holdThreshold,
                        onPressBegan: handlePressBegan,
                        onHoldThresholdCrossed: handleHoldThresholdCrossed,
                        onRelease: handleRelease)
    }

    // MARK: Row scaffold — round mic + separate bordered status bar

    private func micAndBar<Mic: View, Bar: View>(
        @ViewBuilder mic: () -> Mic,
        @ViewBuilder bar: () -> Bar
    ) -> some View {
        HStack(spacing: 8) {
            mic()
            bar()
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(theme.surface)
                .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))
        }
    }

    // MARK: Interactive row (idle/muted/open/held — ONE stable view identity)
    //
    // All the gesture-bearing display states render through this single
    // structural branch, deliberately: the moment a hold's `beginTransmit()`
    // lands, the state flips muted -> transmitting and the body re-renders.
    // If that flip swapped in a different row view (as separate switch
    // branches would), SwiftUI would tear down the gesture's host view
    // mid-press, the in-progress long-press would be cancelled with it, and
    // the release callback could never fire — stranding the mic open with
    // no press left to end it. Conditional CHILDREN (rings, bar copy) may
    // change freely across the flip; the gesture-carrying ZStack itself must
    // keep its structural identity.
    //
    // Mic visual: 44pt round (curation frame 1's dock size) — secondary
    // style (accent stroke, accent glyph) while muted; accent-filled with
    // expanding gsRings while transmitting (1 ring = toggled open, 2 with
    // the frames' 0.7s stagger = held).

    private var interactiveRow: some View {
        micAndBar(mic: {
            ZStack {
                if isTransmitting {
                    GSExpandingRing(color: theme.accent)
                    if isHeldTransmitOwnedByThisPress {
                        GSExpandingRing(color: theme.accent, delay: 0.7)
                    }
                }
                Circle().fill(isTransmitting ? theme.accent : theme.bg)
                if !isTransmitting {
                    Circle().strokeBorder(theme.accent, lineWidth: 1)
                }
                micGlyph(color: isTransmitting ? theme.bg : theme.accent)
            }
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .modifier(pressGesture)
        }, bar: {
            if isTransmitting {
                if isHeldTransmitOwnedByThisPress {
                    holdingBar
                } else {
                    openBar
                }
            } else {
                idleBar
            }
        })
    }

    // MARK: Non-interactive mic variants

    private var connectingMic: some View {
        ZStack {
            Circle().fill(theme.bg)
            Circle().strokeBorder(theme.accent, lineWidth: 1)
            micGlyph(color: theme.accent)
        }
        .frame(width: 44, height: 44)
    }

    private var unavailableMic: some View {
        ZStack {
            Circle().strokeBorder(theme.neutral400, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            Image(systemName: "mic.slash")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(theme.neutral500)
        }
        .frame(width: 44, height: 44)
    }

    private func micGlyph(color: Color) -> some View {
        Image(systemName: "mic")
            .font(.system(size: 18, weight: .regular))
            .foregroundStyle(color)
    }

    // MARK: Status bar variants

    private var idleBar: some View {
        Text("Tap to talk · hold to talk live")
            .font(GSFont.bold(13, relativeTo: .body))
            .foregroundStyle(theme.text.opacity(0.6))
    }

    /// "MIC OPEN · TAP TO MUTE" + REQUIRED sub-caption, per live-voice
    /// frame 2's dock (`:216,223`).
    private var openBar: some View {
        VStack(spacing: 2) {
            Text("MIC OPEN · TAP TO MUTE")
                .font(GSFont.bold(12, relativeTo: .caption))
                .tracking(1.0)
                .foregroundStyle(theme.accent700)
            Text("Tap toggles · press-and-hold for walkie-talkie")
                .font(GSFont.body(10, relativeTo: .caption2))
                .foregroundStyle(theme.neutral500)
        }
        .padding(.vertical, 6)
    }

    /// "HOLDING · {elapsed} — RELEASE TO STOP" with a live counting-up
    /// timer, per live-voice frame 1's dock (`:138`). Composed as sibling
    /// Texts in an HStack (not Text concatenation) so the timer-styled Text
    /// keeps its own self-updating rendering. UI-side only — no Timer, no
    /// service involvement (same doctrine as the chess clock's
    /// `Text(_, style: .timer)`).
    private var holdingBar: some View {
        HStack(spacing: 0) {
            Text("HOLDING · ")
            if let heldStartedAt {
                Text(timerInterval: heldStartedAt...Date.distantFuture,
                     countsDown: false, showsHours: false)
                    .monospacedDigit()
            }
            Text(" — RELEASE TO STOP")
        }
        .font(GSFont.bold(12, relativeTo: .caption))
        .tracking(0.5)
        .foregroundStyle(theme.accent700)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private var connectingBar: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .tint(theme.accent)
            Text("Connecting voice…")
                .font(GSFont.bold(13, relativeTo: .body))
                .foregroundStyle(theme.text)
        }
    }

    private var unavailableBar: some View {
        Text("Voice unavailable")
            .font(GSFont.bold(13, relativeTo: .body))
            .foregroundStyle(theme.neutral500)
    }

    // MARK: Mic denied — entire row becomes one "open Settings" button

    private var deniedRow: some View {
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "mic.slash")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(theme.accent)
                Text("Mic access off — turn on in Settings")
                    .font(GSFont.bold(14, relativeTo: .body))
                    .foregroundStyle(theme.text)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.accent700)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .frame(minHeight: 44)
            .background(theme.bg)
            .overlay(Rectangle().strokeBorder(theme.accent, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Gesture handlers
    //
    // Edge cases verified for OVERLAPPING press cycles, not just single-press
    // ordering (review round 1):
    //   - Coordinator's exact race (hold #1 released at threshold, immediate
    //     hold #2): press #1's stale release Task resumes after press #2
    //     began -> its `gen == pressGeneration` guard fails -> it touches
    //     NOTHING (neither the flags nor the `holdBeginTask` slot). Press
    //     #2's own threshold handler either began a fresh transmission (if
    //     #1's begin hadn't landed yet, state was still .muted) or ADOPTS
    //     the already-live non-toggled transmission (if #1's begin landed
    //     first) — either way #2 ends up owning it, and #2's release ends it.
    //   - Orphan recovery: if a superseded press leaves an unowned, non-
    //     toggled transmission live (its ownership was reset by a newer
    //     press-down), the UI honestly shows the hands-free open state, a
    //     TAP mutes it, and a HOLD adopts it (walkie-talkie: that hold's
    //     release then mutes). The only transmissions release must never
    //     mute are TAP-toggled ones — `isToggledOpen` gates adoption.
    //   - Tap while held-transmitting: not reachable through a single
    //     press/release cycle on one button — a "tap" IS a full press+
    //     release under threshold, so it can't overlap a still-down hold.
    //   - Hold while toggled-open: the adoption branch requires
    //     `!isToggledOpen`, so ownership is never claimed; release falls to
    //     the "threshold crossed but not owned" no-op branch, leaving the
    //     toggled-open mic untouched.
    //   - Release ordering: release captures `holdBeginTask` into a local
    //     `let` and awaits THAT (not the shared slot, which a newer press
    //     may have overwritten), so it can never observe the ownership flag
    //     mid-flight for its own press.
    //   - Disappear during transmit: handled at the service layer —
    //     `VoiceRoomService.leave()` unconditionally restores `.idle`, and
    //     any stale `endTransmit()`/`beginTransmit()` these Tasks fire
    //     afterward is a guarded no-op inside the service.

    private func handlePressBegan() {
        pressGeneration += 1
        holdThresholdCrossedThisPress = false
        // A new press always takes over the per-press flags. If a superseded
        // press's transmission is still live it becomes an unowned orphan —
        // recoverable by this press (tap mutes, hold adopts; see above).
        isHeldTransmitOwnedByThisPress = false
        heldStartedAt = nil
    }

    private func handleHoldThresholdCrossed() {
        holdThresholdCrossedThisPress = true
        let gen = pressGeneration
        holdBeginTask = Task {
            switch voice.state {
            case .connected(.muted):
                await voice.beginTransmit()
                // A newer press owns the shared flags now — a stale hold
                // must not claim ownership on its behalf.
                guard gen == pressGeneration else { return }
                if case .connected(.transmitting) = voice.state {
                    isHeldTransmitOwnedByThisPress = true
                    heldStartedAt = Date()
                }
            case .connected(.transmitting):
                // Adopt an unowned, non-toggled live transmission (orphaned
                // by a superseded earlier press) — walkie-talkie semantics:
                // this press's release stops it. Never adopts a tap-toggled
                // open mic.
                guard gen == pressGeneration,
                      !isToggledOpen,
                      !isHeldTransmitOwnedByThisPress else { return }
                isHeldTransmitOwnedByThisPress = true
                heldStartedAt = Date()
            default:
                break
            }
        }
    }

    private func handleRelease() {
        let gen = pressGeneration
        // Press-local capture: the shared slot may be overwritten by a newer
        // press while this Task is suspended; awaiting the captured
        // reference settles OUR press's in-flight begin without touching
        // anyone else's.
        let inFlightBegin = holdBeginTask
        Task {
            await inFlightBegin?.value
            // A newer press has taken over — stand down completely (don't
            // consume flags, don't clear the slot; they're not ours anymore).
            guard gen == pressGeneration else { return }
            holdBeginTask = nil

            if isHeldTransmitOwnedByThisPress {
                isHeldTransmitOwnedByThisPress = false
                heldStartedAt = nil
                await voice.endTransmit()
            } else if holdThresholdCrossedThisPress {
                // Hold crossed the threshold but never owned a transmission
                // (mic was toggled open) — release must not touch mute state.
            } else {
                await handleTapToggle()
            }
        }
    }

    private func handleTapToggle() async {
        switch voice.state {
        case .connected(.muted):
            await voice.beginTransmit()
            if case .connected(.transmitting) = voice.state {
                isToggledOpen = true
            }
        case .connected(.transmitting):
            await voice.endTransmit()
            // Cleared on every outcome, deliberately without an
            // `if case .connected(.muted)` re-check mirroring the branch
            // above (review round 1, minor (a)): after `endTransmit()` the
            // state is either `.connected(.muted)` (success — no toggled-
            // open mic remains) or a `leave()` interleaved and the room is
            // gone (no mic at all) — `false` is the correct value on every
            // reachable outcome, so a conditional re-check could only ever
            // leave a stale `true` behind on the interleave path.
            isToggledOpen = false
            heldStartedAt = nil
        default:
            break
        }
    }
}

// MARK: - PTTPressGesture
//
// Wraps `onLongPressGesture(minimumDuration:pressing:perform:)` so
// `PTTDockRow`'s interactive mic variants share one gesture wiring instead
// of duplicating the modifier call — see `PTTDockRow`'s doc comment for why
// a single `onLongPressGesture` is enough to derive both tap and hold
// behavior.

private struct PTTPressGesture: ViewModifier {
    let threshold: TimeInterval
    let onPressBegan: () -> Void
    let onHoldThresholdCrossed: () -> Void
    let onRelease: () -> Void

    func body(content: Content) -> some View {
        content.onLongPressGesture(minimumDuration: threshold, pressing: { pressing in
            if pressing {
                onPressBegan()
            } else {
                onRelease()
            }
        }, perform: {
            onHoldThresholdCrossed()
        })
    }
}
