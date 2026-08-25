import Foundation

// MARK: - HealthTriage
//
// The gate that runs BEFORE Coach writes anything (owner sign-off
// 2026-08-25: "Should Coach ever decline to program? — I agree").
//
// The 40-persona stress test found the app would happily program someone
// who had just had a cardiac event, because nothing ever asked. Rather
// than invent a screen, this is the PAR-Q+ (PAR-Q+ Collaboration,
// 2021/2025) — the validated instrument for exactly this decision, whose
// structure is recorded in corpus area 'guideline'.
//
// The product rule is narrow and deliberate: a YES does NOT mean the app
// decides anything medical. It means the app STOPS and refers, because
// "is this person safe to train" is not a judgement a coaching app is
// qualified to make. Declining is the correct behaviour, not a missing
// feature.
enum HealthTriage {

    struct Question: Identifiable, Equatable, Sendable {
        let id: String
        /// Plain-language ask. PAR-Q+ wording, lightly adapted for a chat
        /// surface; the CONDITIONS screened are unchanged.
        let prompt: String
        /// The instrument's own carve-out, where it has one. Shown so an
        /// athlete does not over-report a healed injury or exercise
        /// breathlessness.
        let clarifier: String?
    }

    /// PAR-Q+ Step 1 — the seven general health questions. Order matches
    /// the instrument.
    static let questions: [Question] = [
        Question(id: "heart_or_bp",
                 prompt: "Has a doctor ever said you have a heart condition or high blood pressure?",
                 clarifier: nil),
        Question(id: "chest_pain",
                 prompt: "Do you get chest pain at rest, during daily activities, or when you exercise?",
                 clarifier: nil),
        Question(id: "dizziness",
                 prompt: "Do you lose balance from dizziness, or have you lost consciousness in the last 12 months?",
                 clarifier: "Answer no if the dizziness came from over-breathing during hard exercise."),
        Question(id: "chronic_condition",
                 prompt: "Have you been diagnosed with another chronic medical condition?",
                 clarifier: nil),
        Question(id: "medication",
                 prompt: "Are you currently taking prescribed medication for a chronic condition?",
                 clarifier: nil),
        Question(id: "musculoskeletal",
                 prompt: "Do you have a bone, joint, or soft-tissue problem that training could make worse?",
                 clarifier: "Answer no if it's an old problem that doesn't limit you now."),
        Question(id: "supervised_only",
                 prompt: "Has a doctor said you should only do medically supervised activity?",
                 clarifier: nil),
    ]

    /// The one genuinely blocking temporary state PAR-Q+ names: be ill,
    /// wait until you are not.
    enum DelayReason: String, Equatable, Sendable {
        case acuteIllness

        var copy: String {
            switch self {
            case .acuteIllness:
                return "Let's wait until you're over this. Training through a fever isn't toughness — it's a longer layoff."
            }
        }
    }

    /// Pregnancy is NOT a delay (corrected 2026-08-25). The first pass
    /// read PAR-Q+'s "talk to your practitioner before becoming MORE
    /// physically active" as a stop sign. It is not: ACOG Committee
    /// Opinion 804 encourages aerobic AND strength work before, during and
    /// after pregnancy, and says those already training vigorously may
    /// continue. Blocking here would have been both wrong and
    /// paternalistic — the practitioner conversation is a companion to
    /// training, not a gate in front of it.
    static let pregnancyAdvisory = """
        Training through pregnancy is well supported — the guidance encourages both lifting and cardio,         and if you were already training hard you can generally keep going. Two things I'd ask: loop in         your own practitioner, since they know things I can't, and tell me anything they want changed         so I can build around it.
        """

    static let postpartumAdvisory = """
        Welcome back. Light work is fine as soon as you're cleared, and we'll rebuild from where you         actually are rather than where you left off — same as any return.
        """

    enum Outcome: Equatable, Sendable {
        /// Nothing flagged. Coach may program.
        case cleared
        /// Coach programs AND says something — pregnancy and postpartum
        /// live here, not in `delay`.
        case clearedWithAdvisory(String)
        /// Flagged. Coach does NOT program and says why.
        case referOut(flagged: [String])
        /// Temporary and genuinely blocking. Acute illness only.
        case delay(DelayReason)
    }

    /// States that change the ADVICE without withdrawing the program.
    enum LifeStage: Equatable, Sendable {
        case pregnant, postpartum

        var advisory: String {
            switch self {
            case .pregnant: return HealthTriage.pregnancyAdvisory
            case .postpartum: return HealthTriage.postpartumAdvisory
            }
        }
    }

    /// The decision rule, straight from the instrument: all-NO clears;
    /// any-YES routes onward. Delay conditions outrank clearance, because
    /// someone can be perfectly healthy AND currently feverish.
    static func evaluate(answers: [String: Bool],
                         delay: DelayReason? = nil,
                         stage: LifeStage? = nil) -> Outcome {
        if let delay { return .delay(delay) }
        let flagged = questions.map(\.id).filter { answers[$0] == true }
        if !flagged.isEmpty { return .referOut(flagged: flagged) }
        if let stage { return .clearedWithAdvisory(stage.advisory) }
        return .cleared
    }

    /// What Coach says on a refer-out. Names the boundary honestly rather
    /// than implying a diagnosis, and never leaves the athlete with
    /// nothing.
    static func referralCopy(flagged: [String]) -> String {
        let subject = flagged.contains("chest_pain") || flagged.contains("heart_or_bp")
            ? "what you've told me about your heart"
            : "what you've told me"
        return """
        I'm not going to write you a program yet — \(subject) is a conversation for a doctor, not for me. \
        That isn't me being cautious for the sake of it: picking your loads is exactly the decision that needs \
        someone who can actually examine you.

        Get cleared, tell me what they said, and I'll build around it. In the meantime everything else in here \
        still works — your log, your history, and I'm happy to talk training.
        """
    }

    /// PAR-Q+ clearance is not permanent: it expires, and a change in
    /// health invalidates it early.
    static let clearanceValidityDays = 365

    static func clearanceExpired(clearedAt: Date?, now: Date = .now) -> Bool {
        guard let clearedAt else { return true }
        let days = Calendar.current.dateComponents([.day], from: clearedAt, to: now).day ?? 0
        return days >= clearanceValidityDays
    }
}
