import Foundation

/// Locale-safe user-input parsing for `Decimal` (Phase O Task 2). Pure, no
/// dependencies — same "static-namespace-adjacent, callers pass already-
/// captured strings in" idiom as `PlateMath`/`StatMath` (Models/PlateMath.swift,
/// Models/StatMath.swift), just expressed as an `extension Decimal` (a
/// parse helper reads more naturally as `Decimal.parseUserInput(_:)` than as
/// its own enum namespace).
///
/// THE BUG THIS FIXES: every weight-entry submit path in this codebase used
/// to call the bare `Decimal(string:)` initializer directly on a keyboard-
/// typed string (`.decimalPad` `TextField`s at `BodyWeightLogSheet.swift`,
/// `LogSetSheet.swift`, `GroupSessionLiveView.swift`). `Decimal(string:)`
/// with NO explicit `locale:` argument parses using `Locale.current`'s
/// decimal separator — but a `.decimalPad` keyboard shows a COMMA (not a
/// period) as its decimal key on comma-locale devices (most of continental
/// Europe, Brazil, etc.), and separately, `Decimal(string:)`'s locale-aware
/// parsing is inconsistent about which separator it actually accepts across
/// OS versions/locales. Net effect: a comma-locale user typing "72,5" could
/// get `nil` back — an unsubmittable weight, with no visible error (the
/// submit button in every one of these call sites just silently stays
/// disabled, per each screen's own `canSubmit`/`Int(reps) == nil`-style
/// guard).
///
/// THE FIX: normalize the separator BEFORE handing the string to
/// `Decimal(string:)`, so both "72.5" and "72,5" parse to the same value
/// regardless of device locale. Parse-side only — this never touches how a
/// `Decimal` is FORMATTED for display (`formattedPlateWeight` in
/// LogSetSheet.swift and every other display site are untouched), and never
/// changes what gets STORED (a parsed `Decimal` is locale-agnostic once it
/// exists in memory — `72.5` the value is identical regardless of which
/// separator character produced it).
enum DecimalParsing {
    /// Parses user-typed weight/decimal input, accepting either `.` or `,`
    /// as the decimal separator.
    ///
    /// Algorithm: trim leading/trailing whitespace first and reject an
    /// empty (or whitespace-only) result outright — see "WHITESPACE FIX"
    /// below for why this step exists. Then reject anything with more than
    /// one separator character total (across `.` and `,` combined) — a
    /// string like "1.234,5" or "1,234.5" (thousands-grouped input) is NOT
    /// a case this helper supports; every call site here is a small
    /// numeric-pad field for a single weight/count value, never a
    /// thousands-formatted number, so treating a double-separator string as
    /// invalid (rather than guessing which one is the "real" decimal
    /// point) is the honest behavior — same posture as the pre-existing
    /// `Decimal(string:)` call, which already returned `nil` for malformed
    /// input and every caller already handles that `nil` (disabled submit
    /// button / early return). A comma is then normalized to a period and
    /// handed to `Decimal(string:)` with the FIXED `Locale(identifier:
    /// "en_US_POSIX")` — not `Locale.current` — so parsing behavior is
    /// deterministic and independent of the device's actual locale once the
    /// separator itself has already been normalized.
    ///
    /// WHITESPACE FIX (Phase O Task 2, fix wave 1 — CI-caught: `Decimal
    /// (string:locale:)`/`NSDecimalNumber` parses a whitespace-only string
    /// as `0` rather than failing, so `DecimalParsingTests.
    /// testWhitespaceOnlyIsInvalid` — which correctly expects `nil` — was
    /// failing against the un-trimmed helper). Trimming BEFORE the
    /// separator count/parse also means a string with incidental
    /// leading/trailing whitespace around real digits (`" 5 "`) parses as
    /// `5` rather than failing — a deliberate choice, not a side effect
    /// left unexamined: none of this helper's `.decimalPad` call sites can
    /// actually produce a string with leading/trailing whitespace around
    /// digits today, but accepting it is strictly more permissive/correct
    /// than rejecting it (a keyboard string with stray whitespace around an
    /// otherwise-valid number is still an unambiguous user intent), so
    /// there's no reason to special-case it back to `nil`.
    ///
    /// DIGIT GUARD (fix wave 2 — CI-caught, same Foundation quirk family as
    /// the whitespace fix): `Decimal(string: ".", locale: en_US_POSIX)`
    /// parses to `0`, NOT `nil` — Foundation's scanner treats a digit-free
    /// separator (and other digit-free prefixes) as an empty-but-valid zero
    /// parse. So a lone separator surviving the trim (`" . "` -> `"."`)
    /// must be rejected explicitly: the guard below requires at least one
    /// decimal digit in the normalized string before parsing.
    static func parse(_ input: String) -> Decimal? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let separatorCount = trimmed.filter { $0 == "." || $0 == "," }.count
        guard separatorCount <= 1 else { return nil }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard normalized.contains(where: { $0.isNumber }) else { return nil }
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }
}

extension Decimal {
    /// See `DecimalParsing.parse(_:)` — this is the call-site-friendly
    /// spelling (`Decimal.parseUserInput(weight)`) every submit surface
    /// should use in place of the bare `Decimal(string:)` initializer.
    static func parseUserInput(_ input: String) -> Decimal? {
        DecimalParsing.parse(input)
    }
}
