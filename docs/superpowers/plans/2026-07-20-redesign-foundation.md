# Redesign Plan 1 — Design-System Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the near-black "Onyx" design-system foundation — Onyx palette, decoupled user-selectable accent (default sky blue), radius/elevation tokens — so every screen in later plans has the tokens to build on.

**Architecture:** Extend the existing `GSTheme`/`GSPalettes`/`ThemeStore` system rather than replace it. Add an **Onyx** `GSTheme` palette and make it the default. **Decouple the accent from the palette** via a new `GSAccent` type + `\.gsAccent` environment key + a `user_settings.accent` column, persisted through `ThemeStore` by mirroring the exact race-guarded pattern `select(_:)` already uses for `palette`. Add global `GSMetrics` (radius/elevation) since the whole app moves to rounded/elevated.

**Tech Stack:** SwiftUI, `@Observable` `ThemeStore` (MainActor singleton), Supabase (`user_settings` table), XCTest. Swift compiles only in CI (macos-15, XcodeGen); verify via the ios.yml build-test + screenshots jobs.

## Global Constraints

- Onyx tokens (verbatim): `bg #0A0B0D`, `surface #16181D`, `surface2 #1E222A`, `hair rgba(255,255,255,.07)`, `text #F3F5F8`, `muted #868B95`, `dim #5C616B`. `isDark: true`.
- Accent presets (base / soft / onAccent), default **sky**: sky `#38BDF8`/`rgba(56,189,248,.15)`/`#04222E`; violet `#A78BFA`/`.16`/`#1C1233`; amber `#FFB020`/`.16`/`#2A1C04`; lime `#B6F236`/`.15`/`#1C2A06`; coral `#FF6B5E`/`.16`/`#2E0F0B`; rose `#FB7BB5`/`.16`/`#2E0F20`; mono `#F3F5F8`/`.12`/`#0A0B0D`.
- Radius: `sm 16`, `md 24`, `pill 999`. Elevation md: `color: black, opacity .40, radius 24, y 8`.
- Group colors are NOT in scope here (they belong to the Social/calendar plans); only the personal accent.
- Migrations are append-only via `npx supabase db push` (never edit an applied migration).
- Never `git add -A`; commit only the files each task names. Branch `ui/visual-language-redesign` (already checked out).
- New `UserSettings`/`UserSettingsUpsert` fields go **last with a default** (memberwise-init trap, per `UserSettings.swift:16-26`).

---

### Task 1: `user_settings.accent` column + Onyx default (migration)

**Files:**
- Create: `supabase/migrations/20260720000001_user_settings_accent_and_onyx.sql`

**Interfaces:**
- Produces: a `user_settings.accent text NOT NULL DEFAULT 'sky'` column; `palette` default changed to `'onyx'`; the `palette` CHECK constraint extended to allow `'onyx'`; existing rows migrated to onyx.

- [ ] **Step 1: Write the migration**

```sql
-- 20260720000001_user_settings_accent_and_onyx.sql
-- Redesign foundation: add a user-selectable accent, add the Onyx palette as
-- the new default look, and migrate existing rows onto it. Append-only.

-- 1. Accent column. Free-form text: a preset id ('sky'|'violet'|'amber'|'lime'
--    |'coral'|'rose'|'mono') OR a custom '#rrggbb' hex. No CHECK — the client
--    (GSAccents.accent(for:)) is total and falls back to sky for anything it
--    doesn't recognise, so an odd value degrades to the default, never errors.
ALTER TABLE public.user_settings
  ADD COLUMN IF NOT EXISTS accent text NOT NULL DEFAULT 'sky';

-- 2. Allow 'onyx' in the palette CHECK. The original constraint
--    (20260717000001_user_settings.sql) restricts palette to the four canvas
--    palettes; drop and re-add including onyx.
ALTER TABLE public.user_settings DROP CONSTRAINT IF EXISTS user_settings_palette_check;
ALTER TABLE public.user_settings
  ADD CONSTRAINT user_settings_palette_check
  CHECK (palette IN ('onyx','midnight','arena','ink','modernist'));

-- 3. Onyx is the new default, and the redesign replaces the old look for
--    everyone (pre-GA, no real users to disrupt), so migrate existing rows.
ALTER TABLE public.user_settings ALTER COLUMN palette SET DEFAULT 'onyx';
UPDATE public.user_settings SET palette = 'onyx' WHERE palette <> 'onyx';
```

- [ ] **Step 2: Apply the migration**

Run: `npx supabase db push --db-url "postgresql://postgres.chjkkwqwdlmaxacwglzm:$DB_PASS@aws-0-ca-central-1.pooler.supabase.com:5432/postgres" --yes`
Expected: applies `20260720000001_user_settings_accent_and_onyx`.

- [ ] **Step 3: Verify with a live probe**

Run: `node scripts/db_query.js "SELECT column_default FROM information_schema.columns WHERE table_name='user_settings' AND column_name IN ('palette','accent')"`
Expected: palette default `'onyx'::text`, accent default `'sky'::text`.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260720000001_user_settings_accent_and_onyx.sql
git commit -m "feat(redesign): user_settings.accent column + Onyx default palette"
```

---

### Task 2: `UserSettings.accent` field

**Files:**
- Modify: `GymSyncApp/GymSync/Models/UserSettings.swift`
- Test: `GymSyncApp/GymSyncTests/UserSettingsRepositoryTests.swift` (existing target)

**Interfaces:**
- Consumes: the `accent` column from Task 1.
- Produces: `UserSettings.accent: String` (default `"sky"`), round-tripped through `UserSettingsUpsert`.

- [ ] **Step 1: Write the failing test**

```swift
func test_accent_defaults_to_sky() {
    let s = UserSettings.defaults(userID: UUID())
    XCTAssertEqual(s.accent, "sky")
}
```

- [ ] **Step 2: Run to verify it fails**

Run (CI, or `xcodebuild test` locally on a Mac): expected FAIL — `value of type 'UserSettings' has no member 'accent'`.

- [ ] **Step 3: Add the field (LAST, with a default — memberwise-init trap)**

In `UserSettings` struct, after `shareHeartRate`:
```swift
    /// Redesign foundation — user-selectable accent (preset id or '#rrggbb').
    /// LAST + defaulted for the same memberwise-init reason as shareHeartRate above.
    var accent: String = "sky"
```
Add to `CodingKeys`: `case accent`.
Update `defaults(userID:)`: add `accent: "sky"` as the trailing argument.
In `UserSettingsUpsert`: add `let accent: String`, add `case accent` to its `CodingKeys`, and pass `accent: settings.accent` in `UserSettingsRepository.upsert`'s `UserSettingsUpsert(...)`.

- [ ] **Step 4: Run to verify pass**

Expected PASS.

- [ ] **Step 5: Commit**

```bash
git add GymSyncApp/GymSync/Models/UserSettings.swift GymSyncApp/GymSyncTests/UserSettingsRepositoryTests.swift
git commit -m "feat(redesign): UserSettings.accent field round-tripped through upsert"
```

---

### Task 3: `GSMetrics` (radius + elevation tokens)

**Files:**
- Create: `GymSyncApp/GymSync/DesignSystem/GSMetrics.swift`

**Interfaces:**
- Produces: `GSMetrics.radiusSm/radiusMd/pill: CGFloat`; `View.gsElevation()` modifier (the standard widget shadow).

- [ ] **Step 1: Create the file**

```swift
import SwiftUI

/// Global layout tokens for the near-black redesign. Uniform across the app
/// (not per-palette) — the whole app is rounded/elevated now, unlike the old
/// zero-radius Modernist system.
public enum GSMetrics {
    public static let radiusSm: CGFloat = 16
    public static let radiusMd: CGFloat = 24
    public static let pill: CGFloat = 999
    public static let space1: CGFloat = 4
    public static let space2: CGFloat = 8
    public static let space3: CGFloat = 11
    public static let space4: CGFloat = 16
    public static let space6: CGFloat = 24
}

public extension View {
    /// The standard widget elevation — soft ink shadow on the near-black ground.
    func gsElevation() -> some View {
        shadow(color: .black.opacity(0.40), radius: 24, x: 0, y: 8)
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add GymSyncApp/GymSync/DesignSystem/GSMetrics.swift
git commit -m "feat(redesign): GSMetrics radius/elevation/spacing tokens"
```

---

### Task 4: `GSAccent` + `GSAccents` registry + `\.gsAccent` environment

**Files:**
- Create: `GymSyncApp/GymSync/DesignSystem/GSAccent.swift`
- Test: `GymSyncApp/GymSyncTests/GSAccentTests.swift`

**Interfaces:**
- Consumes: the `Color(hex:)` pattern (replicate locally; the one in GSTheme.swift is fileprivate).
- Produces: `struct GSAccent { let id, base, soft, onAccent }`; `GSAccents.all: [GSAccent]`; `GSAccents.accent(for id: String) -> GSAccent` (total, falls back to sky, parses `#rrggbb`); `EnvironmentValues.gsAccent` (default `GSAccents.sky`).

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import GymSync

final class GSAccentTests: XCTestCase {
    func test_known_preset_resolves() {
        XCTAssertEqual(GSAccents.accent(for: "amber").id, "amber")
    }
    func test_unknown_falls_back_to_sky() {
        XCTAssertEqual(GSAccents.accent(for: "banana").id, "sky")
    }
    func test_custom_hex_parses() {
        XCTAssertEqual(GSAccents.accent(for: "#7c9cff").id, "#7c9cff")
    }
}
```

- [ ] **Step 2: Run to verify fail** — expected FAIL (no `GSAccents`).

- [ ] **Step 3: Implement**

```swift
import SwiftUI

public struct GSAccent: Identifiable, Equatable {
    public let id: String        // preset id or "#rrggbb"
    public let name: String
    public let base: Color
    public let soft: Color
    public let onAccent: Color
}

public enum GSAccents {
    public static let sky    = GSAccent(id: "sky",    name: "Sky blue", base: .hexA(0x38BDF8), soft: .hexA(0x38BDF8, 0.15), onAccent: .hexA(0x04222E))
    public static let violet = GSAccent(id: "violet", name: "Violet",   base: .hexA(0xA78BFA), soft: .hexA(0xA78BFA, 0.16), onAccent: .hexA(0x1C1233))
    public static let amber  = GSAccent(id: "amber",  name: "Amber",    base: .hexA(0xFFB020), soft: .hexA(0xFFB020, 0.16), onAccent: .hexA(0x2A1C04))
    public static let lime   = GSAccent(id: "lime",   name: "Lime",     base: .hexA(0xB6F236), soft: .hexA(0xB6F236, 0.15), onAccent: .hexA(0x1C2A06))
    public static let coral  = GSAccent(id: "coral",  name: "Coral",    base: .hexA(0xFF6B5E), soft: .hexA(0xFF6B5E, 0.16), onAccent: .hexA(0x2E0F0B))
    public static let rose   = GSAccent(id: "rose",   name: "Rose",     base: .hexA(0xFB7BB5), soft: .hexA(0xFB7BB5, 0.16), onAccent: .hexA(0x2E0F20))
    public static let mono   = GSAccent(id: "mono",   name: "Mono",     base: .hexA(0xF3F5F8), soft: .hexA(0xF3F5F8, 0.12), onAccent: .hexA(0x0A0B0D))

    public static let all: [GSAccent] = [sky, violet, amber, lime, coral, rose, mono]

    /// Total: a known preset id, else a parseable '#rrggbb' custom, else sky.
    public static func accent(for id: String) -> GSAccent {
        if let preset = all.first(where: { $0.id == id }) { return preset }
        if let custom = customHex(id) { return custom }
        return sky
    }

    private static func customHex(_ s: String) -> GSAccent? {
        guard s.hasPrefix("#"), s.count == 7, let v = UInt32(s.dropFirst(), radix: 16) else { return nil }
        let base = Color.hexA(v)
        // onAccent: dark ink for light hues, near-white for dark hues (luminance split).
        let r = Double((v >> 16) & 0xff), g = Double((v >> 8) & 0xff), b = Double(v & 0xff)
        let lum = (0.299*r + 0.587*g + 0.114*b) / 255.0
        return GSAccent(id: s, name: "Custom", base: base, soft: base.opacity(0.15),
                        onAccent: lum > 0.6 ? .hexA(0x0A0B0D) : .hexA(0xF3F5F8))
    }
}

public extension Color {
    static func hexA(_ hex: UInt32, _ alpha: Double = 1) -> Color {
        Color(red: Double((hex >> 16) & 0xff)/255, green: Double((hex >> 8) & 0xff)/255,
              blue: Double(hex & 0xff)/255, opacity: alpha)
    }
}

private struct GSAccentKey: EnvironmentKey { static let defaultValue = GSAccents.sky }
public extension EnvironmentValues {
    var gsAccent: GSAccent {
        get { self[GSAccentKey.self] }
        set { self[GSAccentKey.self] = newValue }
    }
}
```

- [ ] **Step 4: Run to verify pass** — expected PASS.

- [ ] **Step 5: Commit**

```bash
git add GymSyncApp/GymSync/DesignSystem/GSAccent.swift GymSyncApp/GymSyncTests/GSAccentTests.swift
git commit -m "feat(redesign): GSAccent presets + custom-hex + gsAccent environment"
```

---

### Task 5: Onyx `GSTheme` palette + registry

**Files:**
- Modify: `GymSyncApp/GymSync/DesignSystem/GSTheme.swift`
- Test: `GymSyncApp/GymSyncTests/GSPalettesTests.swift`

**Interfaces:**
- Consumes: `GSTheme` initializer (surfaces + accent ramp + neutral ramp + isDark).
- Produces: `GSTheme.onyx`; `GSPalettes.all` includes onyx first; `GSPalettes.theme(for: "onyx")` returns it; env default `\.gsTheme` = `.onyx`.

- [ ] **Step 1: Write the failing test**

```swift
func test_onyx_registered_and_default() {
    XCTAssertEqual(GSPalettes.all.first?.id, "onyx")
    XCTAssertEqual(GSPalettes.name(for: "onyx"), "Onyx")
}
```

- [ ] **Step 2: Run to verify fail** — expected FAIL.

- [ ] **Step 3: Add the Onyx palette.** In `GSTheme.swift`, add after the `midnight` static (its accent ramp is a placeholder — new components read `\.gsAccent`, not `theme.accent`, but the field must be non-nil so reuse midnight's cyan ramp values):

```swift
    // MARK: - Onyx palette (redesign default) — near-black surfaces.
    public static let onyx = GSTheme(
        bg:         Color(hex: 0x0A0B0D),
        surface:    Color(hex: 0x16181D),
        text:       Color(hex: 0xF3F5F8),
        divider:    Color.white.opacity(0.07),
        accent:     Color(hex: 0x38BDF8),   // placeholder; UI reads \.gsAccent
        accent100:  Color(hex: 0x0E2C3A), accent200: Color(hex: 0x123A4D), accent300: Color(hex: 0x17506B),
        accent600:  Color(hex: 0x22A6E4), accent700: Color(hex: 0x7DD3FC), accent800: Color(hex: 0xBAE6FD),
        neutral100: Color(hex: 0x16181D),   // surface
        neutral300: Color(hex: 0x1E222A),   // surface2
        neutral400: Color(hex: 0x3A414B), neutral500: Color(hex: 0x5C616B), neutral700: Color(hex: 0x868B95),
        neutral800: Color(hex: 0xCFD4DB), neutral900: Color(hex: 0xF3F5F8),
        isDark: true
    )
```
Register it FIRST in `GSPalettes.all`:
```swift
        GSPaletteOption(id: "onyx", name: "Onyx", subtitle: "Near-black · your accent", theme: .onyx),
```
Change the env default: `GSThemeKey.defaultValue: GSTheme = .onyx`.

- [ ] **Step 4: Run to verify pass** — expected PASS.

- [ ] **Step 5: Commit**

```bash
git add GymSyncApp/GymSync/DesignSystem/GSTheme.swift GymSyncApp/GymSyncTests/GSPalettesTests.swift
git commit -m "feat(redesign): Onyx GSTheme palette, registered as default"
```

---

### Task 6: `ThemeStore` accent state + persistence

**Files:**
- Modify: `GymSyncApp/GymSync/DesignSystem/ThemeStore.swift`
- Test: `GymSyncApp/GymSyncTests/ThemeStoreMergeTests.swift` (existing target)

**Interfaces:**
- Consumes: `GSAccents.accent(for:)` (Task 4), `UserSettings.accent` (Task 2).
- Produces: `ThemeStore.accentID: String`, `accent: GSAccent`, `selectAccent(_ id: String)`; `load()` also applies accent; the persist path writes accent.

- [ ] **Step 1: Write the failing test** (mirrors the existing merge-rule tests)

```swift
func test_merge_protects_accent_like_palette_when_persist_in_flight() {
    var cached = UserSettings.defaults(userID: UUID()); cached.accent = "amber"
    var incoming = cached; incoming.accent = "lime"; incoming.defaultRestSeconds = 90
    let merged = ThemeStore.mergeExternalSettingsWrite(cached: cached, incoming: incoming, persistInFlight: true)
    // accent, like palette, is owned by the in-flight selectAccent task -> keep cached
    XCTAssertEqual(merged.accent, "amber")
    XCTAssertEqual(merged.defaultRestSeconds, 90) // non-owned field adopts incoming
}
```

- [ ] **Step 2: Run to verify fail** — expected FAIL (merge doesn't protect accent yet).

- [ ] **Step 3: Implement.** Add stored state near `paletteID`:
```swift
    public private(set) var accentID: String = "sky"
    public private(set) var accent: GSAccent = GSAccents.sky
```
In `apply(paletteID:)` add a sibling `applyAccent`:
```swift
    private func applyAccent(_ id: String) {
        self.accentID = id
        self.accent = GSAccents.accent(for: id)
    }
```
Call `applyAccent(settings.accent)` inside `load()` (after `apply(paletteID:)`).
Add `selectAccent`, mirroring `select(_:)` exactly but writing `updated.accent`:
```swift
    public func selectAccent(_ id: String) {
        applyAccent(id)
        persistTask?.cancel(); persistGeneration += 1; let generation = persistGeneration
        persistTask = Task {
            defer { if generation == persistGeneration { persistTask = nil } }
            guard let userID = await SupabaseService.shared.currentUserID() else { return }
            var updated = lastKnownSettings ?? UserSettings.defaults(userID: userID)
            updated.accent = id
            guard !Task.isCancelled else { return }
            let ok = (try? await UserSettingsRepository.upsert(updated)) != nil
            guard !Task.isCancelled, ok else { return }
            lastKnownSettings = updated
        }
    }
```
Extend `mergeExternalSettingsWrite`: after the palette-protect guard, the in-flight task now also owns `.accent`, so it is NOT adopted from incoming — leave `merged.accent` as cached (do nothing; `merged` starts as a copy of `cached`, so accent is already retained). Adopt only `defaultRestSeconds` + `shareHeartRate` as today. (No code change needed beyond confirming accent is not overwritten — add a comment documenting accent joins palette on the protected side.)

- [ ] **Step 4: Run to verify pass** — expected PASS.

- [ ] **Step 5: Commit**

```bash
git add GymSyncApp/GymSync/DesignSystem/ThemeStore.swift GymSyncApp/GymSyncTests/ThemeStoreMergeTests.swift
git commit -m "feat(redesign): ThemeStore accent state + race-guarded persistence"
```

---

### Task 7: Inject `\.gsAccent` app-wide from `ThemeStore`

**Files:**
- Modify: `GymSyncApp/GymSync/App/RootView.swift` (the view that injects `\.gsTheme`, per ThemeStore.swift:5-6)

**Interfaces:**
- Consumes: `ThemeStore.shared.current` (already injected as `\.gsTheme`) and `.accent` (Task 6).
- Produces: `\.gsAccent` populated app-wide so every later component reads the live user accent.

- [ ] **Step 1: Add the injection.** Where RootView already sets `.environment(\.gsTheme, ThemeStore.shared.current)`, add on the same view:
```swift
        .environment(\.gsAccent, ThemeStore.shared.accent)
```
(Read the file first to match the exact modifier chain + the `@State`/observation pattern it uses for `ThemeStore.shared`.)

- [ ] **Step 2: Verify in CI.** Push the branch; confirm the ios.yml `build-test` job is green (compiles) and the `screenshots` job still runs. No behavior change yet — accent isn't consumed by any component until Plan 2.

- [ ] **Step 3: Commit**

```bash
git add GymSyncApp/GymSync/App/RootView.swift
git commit -m "feat(redesign): inject live gsAccent environment app-wide"
```

---

## Foundation done — what Plan 2 builds on

After this plan: Onyx is the default palette (near-black), radius/elevation tokens exist, and every view can read `\.gsTheme` (surfaces) + `\.gsAccent` (the user's live accent). **Plan 2 (Components)** restyles `GSComponents` to the Onyx tokens (rounded, elevated, the button-label-fill fix), adds the widget primitives (StatTile, PRCard, StreakRing, Widget), and the `AccentPicker`. **Plan 3 (Home)** rebuilds `HomeView` against the proof + adds empty states, then rebases the parity baseline. Later plans cover the remaining tabs, deep screens, and the emoji cleanup, per spec §8/§10.

## Self-review notes

- **Spec coverage:** implements spec §3 (tokens, decoupled accent, Onyx) + §4's personal-accent half + §8's foundation task group. Group colors (§4 second half), components (§5), empty states (§6), emoji (§7), and per-screen work are explicitly deferred to later plans — each its own testable unit.
- **Type consistency:** `accent: String` (id/hex) is the wire format everywhere (`UserSettings`, `ThemeStore.accentID`, `GSAccents.accent(for:)`); `GSAccent` is the resolved value type carried by `\.gsAccent`. `GSMetrics`/`gsElevation()` names match across tasks.
- **No behavioral risk in isolation:** Tasks 1-7 add tokens/state/columns but no component consumes `\.gsAccent` or `GSMetrics` until Plan 2, so the app looks unchanged (except Onyx surfaces via the palette default) until components are restyled — a safe, independently-shippable foundation.
