import Foundation

// MARK: - SessionStyle
//
// How a crew session moves (spec §1, owner decision 1; plan task S1).
//
// The raw values ARE `sessions.style`'s CHECK constraint
// (`20260913000101_session_style_stations_round.sql`, plan task D1:
// `CHECK (style IN ('rounds','freestyle','together'))`), which is why this is
// a `String` enum and not an `Int` one: the column is readable in psql, and a
// renamed case here is a migration rather than a refactor.
//
// The style is a CREW decision, not the organizer's: any participant may set
// it in the lobby, and `private.session_round_guard` (plan task D3) freezes it
// the moment `lifting_started_at` is stamped. The lobby card (plan task S2)
// stops rendering at that same moment, so the UI never offers a write the
// server will reject.
enum SessionStyle: String, Codable, CaseIterable, Sendable {
    case rounds
    case freestyle
    case together
}

// MARK: - SessionStyleCopy
//
// One spelling of every word the three styles print, asserted by
// `SessionStyleTests`. The lobby card (S2), the style router's doc comment
// (S5) and the catalog's frame 136 all read from here — copy repeated in two
// view bodies is copy that drifts, and a crew that picked "Together" must not
// find it called something else once the session starts.
struct SessionStyleCopy: Equatable, Sendable {
    /// The row's name. Title case: it is a proper noun for a way of lifting.
    let title: String
    /// The consequence, in one sentence — what the crew is agreeing to, not
    /// what the feature is called (design rule 9: sentence case).
    let line: String
    /// An SF Symbol. Never an emoji (design rule 9).
    let glyph: String

    static func of(_ style: SessionStyle) -> SessionStyleCopy {
        switch style {
        case .rounds:
            return SessionStyleCopy(
                title: "Rounds",
                line: "One set each. The round closes when the last lifter logs.",
                glyph: "arrow.triangle.2.circlepath"
            )
        case .freestyle:
            return SessionStyleCopy(
                title: "Freestyle",
                line: "Own pace, one shared rail — you finish together.",
                glyph: "arrow.left.and.right"
            )
        case .together:
            return SessionStyleCopy(
                title: "Together",
                line: "One clock for everyone. No turns.",
                glyph: "timer"
            )
        }
    }
}

extension SessionStyle {
    /// `style.copy.title` at a call site, `SessionStyleCopy.of(style)` at a
    /// test. One table, two spellings of the lookup.
    var copy: SessionStyleCopy { SessionStyleCopy.of(self) }
}

// MARK: - SessionStyleDefault
//
// Spec §6 asks for "a default per routine type computed client-side". There
// is no routine type: `routines` (`20260709000005_create_routines.sql:1-9`)
// has no such column, and the plan's data decision 2 ruled against adding
// one — the only signals live on the routine's own rows, and they are enough.
//
// The rule, whole:
//
//     every non-mobility row is category == "cardio",
//     OR any row carries cardio_minutes            ->  .together
//     otherwise                                    ->  .rounds
//
// Freestyle is NEVER a default. Owner decision 1 named defaults for strength
// and for cardio/HIIT/biking only; Freestyle is a choice the crew makes, and
// a default nobody chose is not that.
//
// This is a pure function so the lobby can call it before any write exists
// (plan task S2 applies it once, on the organizer's client only).
enum SessionStyleDefault {

    /// The routine's rows, reduced to the two columns that carry any signal:
    /// `exercises.category` (`20260709000002:5` —
    /// `compound|isolation|cardio|mobility`) and
    /// `routine_exercises.cardio_minutes` (`20260814000009:11`).
    static func style(forExercises rows: [(category: String, cardioMinutes: Int?)]) -> SessionStyle {
        // A routine that prescribes minutes has a clock in it, whatever its
        // exercises are categorised as.
        if rows.contains(where: { $0.cardioMinutes != nil }) { return .together }

        // Mobility is warm-up furniture: it neither makes a routine cardio
        // nor stops one being cardio.
        let counted = rows.filter { $0.category.lowercased() != "mobility" }

        // Ignoring every row is not the same as "every row is cardio". A
        // mobility-only (or empty) routine has no cardio in it at all, so it
        // is Rounds — a crew with no plan is a rack crew. Without this guard
        // `allSatisfy` would answer `true` vacuously and default an empty
        // routine to Together.
        guard !counted.isEmpty else { return .rounds }

        return counted.allSatisfy { $0.category.lowercased() == "cardio" } ? .together : .rounds
    }
}
