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

    // MARK: - Step 2 (follow-ups)
    //
    // PAR-Q+ Step 1 is a ROUTER, not a verdict. Its own decision rule, in
    // the corpus verbatim (strong): "all seven answered NO means cleared
    // to become more physically active; any YES routes the person to the
    // follow-up condition pages or a clinician conversation." We shipped
    // only the second branch, so a single YES refused to program someone
    // forever — every asthmatic, every statin user, every person on
    // levothyroxine got byte-identical treatment to unstable angina.
    //
    // We do NOT hold the instrument's real follow-up text. Re-verified
    // against all 1,071 findings: ePARmed-X+ appears 0 times, "asthma" 0,
    // "well-controlled" 0. So nothing here reproduces a medical
    // questionnaire we cannot cite. What the corpus DOES give, strongly,
    // is the discriminator the follow-up pages turn on: "across PAR-Q+
    // follow-up categories the recurring discriminator is CONTROL —
    // difficulty controlling a condition with prescribed medication or
    // therapy escalates it toward referral."
    //
    // So the follow-ups ask about CONTROL, SYMPTOMS and CURRENT ACTIVITY,
    // which are the three inputs the ACSM algorithm also names, and
    // nothing about which condition it is. That boundary is deliberate:
    // NSCA, verbatim, "practicing medicine is not within the scope of
    // practice for the personal trainer" — a trainer uses a validated
    // questionnaire "only to identify when to refer".

    /// Which Step-1 answers open follow-ups, and which are terminal.
    ///
    /// HARD flags take no follow-up: chest pain at rest or on exertion,
    /// syncope within 12 months, and a doctor's explicit instruction to
    /// train only under supervision. No self-reported answer can overturn
    /// any of those, and asking six more questions before refusing would
    /// be theatre.
    /// heart_or_bp is HERE, not in the follow-up set, and that is a
    /// deliberate narrowing. The corpus does license clearing a diagnosed,
    /// controlled, asymptomatic, already-active adult — but only "for
    /// light-to-moderate intensity, with clearance before progressing to
    /// vigorous", and that row is HEDGED. Honouring it would mean shipping
    /// an intensity ceiling; clearing without one would go further than
    /// the evidence allows, on the question the corpus separately calls
    /// "the highest-priority stop sign in a self-report screen". So a
    /// cardiac answer keeps referring until the ceiling exists.
    static let hardFlags: Set<String> = ["chest_pain", "dizziness",
                                         "supervised_only", "heart_or_bp"]

    /// Flags that route to the shared condition follow-up. Medication is
    /// a proxy for the condition rather than a separate one, so answering
    /// yes to both asks the follow-up once.
    static let conditionFlags: Set<String> = ["chronic_condition", "medication"]

    /// A musculoskeletal problem is a CONSTRAINT, not a gate. The
    /// instrument's own Q6 "explicitly excludes past musculoskeletal
    /// problems that do not limit current activity", and the clinical
    /// record is that "specific exercises are removed from the program
    /// rather than the entire program being halted". So this one narrows
    /// selection instead of withdrawing the program.
    static let constraintFlags: Set<String> = ["musculoskeletal"]

    struct FollowUp: Identifiable, Equatable, Sendable {
        let id: String
        let prompt: String
        var clarifier: String? = nil
        let options: [Option]

        struct Option: Identifiable, Equatable, Sendable {
            let id: String
            let label: String
            /// Whether choosing this sends the athlete to a clinician.
            let escalates: Bool
        }
    }

    /// The condition follow-up, asked once for any of `conditionFlags`.
    static let conditionFollowUps: [FollowUp] = [
        FollowUp(id: "control",
                 prompt: "Do you have trouble keeping it under control with what your doctor has you on?",
                 clarifier: "Under control is the ordinary case, and it is not a problem for training.",
                 options: [
                    FollowUp.Option(id: "controlled", label: "NO — IT'S UNDER CONTROL", escalates: false),
                    FollowUp.Option(id: "uncontrolled", label: "YES — IT'S NOT SETTLED", escalates: true),
                 ]),
        FollowUp(id: "symptoms",
                 prompt: "Have you had any of these lately?",
                 // The ACSM signs-and-symptoms list, in plain words. We
                 // record only WHETHER, never which: we refer either way,
                 // and storing which symptom edges toward holding clinical
                 // data we have no business holding.
                 clarifier: "Chest, neck, jaw or arm pain · breathless at rest or on light effort · dizziness or fainting · breathless lying down or waking short of breath · swollen ankles · a racing or thumping heart · leg cramping when you walk · a heart murmur · unusual tiredness.",
                 options: [
                    FollowUp.Option(id: "none", label: "NONE OF THESE", escalates: false),
                    FollowUp.Option(id: "any", label: "ANY OF THESE", escalates: true),
                 ]),
        FollowUp(id: "active_now",
                 prompt: "Are you exercising regularly at the moment?",
                 // The corpus carries ACSM's operational definition and it
                 // is quoted rather than paraphrased, because "regularly"
                 // means very different things to different people and the
                 // answer decides a referral.
                 clarifier: "Regularly means at least 30 minutes of moderate exercise, 3 days a week, for the last 3 months.",
                 options: [
                    FollowUp.Option(id: "active", label: "YES", escalates: false),
                    FollowUp.Option(id: "inactive", label: "NO", escalates: true),
                 ]),
    ]

    /// The musculoskeletal follow-up. Never escalates on the area itself.
    static let constraintFollowUps: [FollowUp] = [
        FollowUp(id: "msk_prohibited",
                 prompt: "Has anyone told you not to train it?",
                 clarifier: "A doctor or physio saying to stay off it is different from it being sore.",
                 options: [
                    FollowUp.Option(id: "allowed", label: "NO", escalates: false),
                    FollowUp.Option(id: "prohibited", label: "YES", escalates: true),
                 ]),
        FollowUp(id: "msk_area",
                 prompt: "Which area?",
                 clarifier: "I'll sort exercises that load it to the back of the list.",
                 // Exactly the joints the catalog labels, so an answer
                 // always lands on something selection can act on — the
                 // same discipline ConsultVocabulary uses. An invented
                 // area would record cleanly and change nothing.
                 options: [
                    FollowUp.Option(id: "shoulder", label: "SHOULDER", escalates: false),
                    FollowUp.Option(id: "lower_back", label: "LOWER BACK", escalates: false),
                    FollowUp.Option(id: "knee", label: "KNEE", escalates: false),
                    FollowUp.Option(id: "elbow", label: "ELBOW", escalates: false),
                    FollowUp.Option(id: "wrist", label: "WRIST", escalates: false),
                    FollowUp.Option(id: "hip", label: "HIP", escalates: false),
                    FollowUp.Option(id: "ankle", label: "ANKLE", escalates: false),
                 ]),
    ]

    /// Every follow-up this athlete still owes an answer to, in order.
    static func pendingFollowUps(answers: [String: Bool],
                                 followUps: [String: String]) -> [FollowUp] {
        let flagged = questions.map(\.id).filter { answers[$0] == true }
        // A hard flag ends the conversation; no follow-up can move it.
        guard flagged.allSatisfy({ !hardFlags.contains($0) }) else { return [] }
        var due: [FollowUp] = []
        if flagged.contains(where: conditionFlags.contains) {
            due += conditionFollowUps
        }
        if flagged.contains(where: constraintFlags.contains) {
            due += constraintFollowUps
        }
        return due.filter { followUps[$0.id] == nil }
    }

    /// The Step-1 flags whose follow-ups carry an escalating answer.
    static func escalating(flagged: [String],
                           followUps: [String: String]) -> [String] {
        flagged.flatMap { flag -> [String] in
            let set = conditionFlags.contains(flag) ? conditionFollowUps
                    : constraintFlags.contains(flag) ? constraintFollowUps : []
            let didEscalate = set.contains { followUp in
                followUp.options.contains { $0.id == followUps[followUp.id] && $0.escalates }
            }
            return didEscalate ? [flag] : []
        }
    }

    /// The joint an athlete named, for TrainingProfile.cautionJoints.
    static func cautionJoint(from followUps: [String: String]) -> String? {
        followUps["msk_area"]
    }

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
        Training through pregnancy is well supported — the guidance encourages both lifting and cardio, and if you were already training hard you can generally keep going. Two things I'd ask: loop in your own practitioner, since they know things I can't, and tell me anything they want changed so I can build around it.
        """

    static let postpartumAdvisory = """
        Welcome back. Light work is fine as soon as you're cleared, and we'll rebuild from where you actually are rather than where you left off — same as any return.
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
        /// A follow-up is owed. NOT a refusal and NOT a clearance — we do
        /// not know yet. The gate resumes at this question rather than
        /// showing a declined card, which is what stops one YES from
        /// reading as a verdict.
        case incomplete(next: FollowUp)
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
                         followUps: [String: String] = [:],
                         delay: DelayReason? = nil,
                         stage: LifeStage? = nil) -> Outcome {
        if let delay { return .delay(delay) }
        let flagged = questions.map(\.id).filter { answers[$0] == true }
        if flagged.isEmpty {
            if let stage { return .clearedWithAdvisory(stage.advisory) }
            return .cleared
        }
        // A hard flag is terminal.
        let hard = flagged.filter(hardFlags.contains)
        if !hard.isEmpty { return .referOut(flagged: hard) }

        // An ESCALATING answer already given ends it, before anything
        // else is asked. Someone who has just said a doctor told them not
        // to train that joint must not then be asked WHICH joint before
        // being refused - the same "no more theatre" rule the hard flags
        // follow, applied to an answer rather than to a question.
        let escalatedNow = escalating(flagged: flagged, followUps: followUps)
        if !escalatedNow.isEmpty { return .referOut(flagged: escalatedNow) }

        // Otherwise, unanswered follow-ups mean we do not KNOW yet, which
        // is neither cleared nor refused. Returning .referOut here is what
        // made a single YES a permanent refusal.
        let pending = pendingFollowUps(answers: answers, followUps: followUps)
        if let next = pending.first { return .incomplete(next: next) }
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
