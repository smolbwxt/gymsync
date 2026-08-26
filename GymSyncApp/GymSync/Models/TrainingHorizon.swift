import Foundation

// MARK: - TrainingHorizon
//
// "Which of these sets belong to the athlete they are NOW?"
//
// The corpus names one failure mode for a returning lifter, and rates it
// against injury: "chasing pre-layoff numbers or a training partner's
// effort too soon; the resulting injury costs far more long-term time
// than a deliberately slow ramp back." The app used to perform it FOR
// them — three separate places read an athlete's whole logged history
// with no recency bound, so a lifter two years away had a two-year-old
// PR projected onto the bar on their first session back, and was told
// three sessions later that they had stalled for 730 days.
//
// WHY THIS IS A TYPE AND NOT A PARAMETER
//
// The obvious fix is `historySince:` threaded through every function that
// reads history. It was rejected: `BlockProgression.decide` alone has
// four call sites, two of which an initial design missed, and a fifth
// added next year would silently reintroduce the defect with nothing to
// catch it. A defaulted parameter callers must remember is precisely this
// repo's dominant failure — a rule with no call site.
//
// So the horizon is INTRINSIC to the engines that prescribe: they derive
// it from the history they were already handed. There is nothing for a
// caller to pass and therefore nothing to forget.
//
// WHERE IT DELIBERATELY DOES NOT APPLY
//
// Prescription is not narration. `WorkingWeight.bestQualifyingSet` stays
// horizon-free because it also answers "what is their best ever?" for PR
// copy and debrief recaps, and hiding a real personal record from the
// person who set it is a product decision nobody has taken. The rule is:
// anything that puts a number on the bar reads the horizon; anything that
// tells the athlete about their own history does not.
enum TrainingHorizon {

    /// The day training RESUMED after the most recent layoff, or nil when
    /// the log shows no layoff to have returned from.
    ///
    /// nil means "no gap found", NOT "no gap exists" — a history window
    /// too short to contain the gap returns nil, and callers get their
    /// unfiltered input back. That failure direction is deliberate: the
    /// alternative is inventing a horizon out of missing data.
    static func returnDate(in logs: [SetLog],
                           now: Date = .now,
                           layoffDays: Int = GeneratorScience.layoffResetDays,
                           calendar: Calendar = .current) -> Date? {
        let dates = logs.map(\.loggedAt)
        // THE FIRST SESSION BACK. The gap that matters on day one is not
        // between two logged sets — it is between the last logged set and
        // TODAY, and a gap-walk over logged dates alone cannot see it. Miss
        // this and the horizon fails to fire at the exact moment it exists
        // for: an athlete opening the app after two years, with every set
        // on file from before the layoff and a two-year-old PR one rung
        // away from the bar.
        //
        // The whole log is then pre-layoff, so `sinceReturn` yields
        // nothing and every history-fed rung correctly goes quiet.
        if let last = dates.max() {
            let idle = calendar.dateComponents([.day],
                                               from: calendar.startOfDay(for: last),
                                               to: calendar.startOfDay(for: now)).day ?? 0
            if idle >= layoffDays { return calendar.startOfDay(for: now) }
        }
        // Otherwise: a gap BETWEEN two logged sessions, i.e. they came back
        // at some point and have been training since.
        return GeneratorScience.returnDate(sessionDates: dates,
                                           layoffDays: layoffDays,
                                           calendar: calendar)
    }

    /// The sets that belong to the current training era.
    ///
    /// Returns the input UNCHANGED when there is no layoff, so this is
    /// safe to apply unconditionally at any prescription site — the
    /// no-layoff case, which is almost everyone almost always, is exactly
    /// a pass-through.
    static func sinceReturn(_ logs: [SetLog],
                            now: Date = .now,
                            layoffDays: Int = GeneratorScience.layoffResetDays,
                            calendar: Calendar = .current) -> [SetLog] {
        guard let resumed = returnDate(in: logs, now: now, layoffDays: layoffDays,
                                       calendar: calendar) else { return logs }
        return logs.filter { calendar.startOfDay(for: $0.loggedAt) >= resumed }
    }

    /// Whether this history crosses a layoff — i.e. whether the athlete is
    /// inside a return. Used to decide whether to SAY something, not to
    /// decide a number.
    static func isReturning(_ logs: [SetLog],
                            now: Date = .now,
                            layoffDays: Int = GeneratorScience.layoffResetDays,
                            calendar: Calendar = .current) -> Bool {
        returnDate(in: logs, now: now, layoffDays: layoffDays, calendar: calendar) != nil
    }

    /// What Coach says when the horizon leaves nothing to prescribe from.
    ///
    /// The corpus refuses a percentage anchor for return outright —
    /// "Return loads should be set using RPE 5-6 rather than a percentage
    /// of pre-layoff maxes, letting current capacity -- not history --
    /// determine the actual working weight" — and its worked example is a
    /// lifter who "rebuilt every working weight from an empty bar using
    /// feel rather than resuming old numbers". So a 60%-of-old-max haircut
    /// would be BOTH our invention and against the evidence. An empty
    /// field with a sentence beats a confident wrong number, which is the
    /// law WorkingWeight already states: "A wrong prefilled weight is
    /// worse than none, because someone will load it."
    static let emptyBarNote = "First session back. Pick a weight that feels like a 5 or 6 out of 10 and stop there — we'll rebuild your numbers from what you actually do, not from what you used to lift."
}
