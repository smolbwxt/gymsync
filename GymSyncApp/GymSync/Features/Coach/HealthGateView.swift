import SwiftUI

// MARK: - HealthGateView
//
// The PAR-Q+ screening, as a COMPONENT rather than a phase inside one
// screen.
//
// It began life inside CoachConsultView, which meant the gate guarded
// exactly one of the four doors into the generator: the wizard is also
// presented from RootView, from two places on the Coach home, and from
// the block calendar, and none of those screened anyone. An athlete who
// never opened the consult — including a brand-new user taking the
// post-walkthrough offer — was prescribed loads with no screening at all.
// That is the precise failure the 40-persona sweep surfaced, still open on
// three paths out of four.
//
// Extracting it also avoids the worse fix. Copying the screening into the
// wizard would have put two implementations of a medical gate in the
// codebase, and they would drift — one would gain a question, or a
// different expiry rule, and both halves would still look correct on their
// own. There is one gate.
//
// The host decides WHAT is gated. This view only answers "is this athlete
// cleared, and what should Coach say about it?"
struct HealthGateView: View {
    @Environment(\.gsTheme) private var theme

    /// Needed to persist. Optional because a signed-out state must still
    /// be able to READ the gate; it just cannot record anything.
    let userID: UUID?

    /// Fires once the athlete is cleared to be programmed, carrying the
    /// advisory when there is one (pregnancy and postpartum clear WITH
    /// something to say — ACOG 804 — rather than being blocked).
    var onCleared: (String?) -> Void

    @State private var screening = HealthScreening()
    @State private var index = 0
    @State private var phase: Phase = .loading
    @State private var started = false

    private enum Phase: Equatable {
        case loading
        /// One question in front of the seven. A NO clears; a YES opens
        /// the full instrument.
        case preScreen
        case screening
        /// Step 2. A YES in Step 1 opens a follow-up rather than ending
        /// the conversation — see HealthTriage.pendingFollowUps.
        case followUp(HealthTriage.FollowUp)
        /// Coach does not program, and says why.
        case declined(HealthTriage.Outcome)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch phase {
            case .loading:
                Spacer(minLength: 0)
            case .preScreen:
                preScreenPhase
            case .screening:
                screeningPhase
            case .followUp(let followUp):
                followUpPhase(followUp)
            case .declined(let outcome):
                declinedCard(outcome)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear(perform: start)
    }

    // MARK: The pre-screen

    @ViewBuilder
    private var preScreenPhase: some View {
        let question = HealthTriage.preScreen
        VStack(alignment: .leading, spacing: 8) {
            Text("BEFORE WE START")
                .font(GSFont.bold(10, relativeTo: .caption2))
                .tracking(1.1)
                .foregroundStyle(theme.accent)
            Text(question.prompt)
                .font(GSFont.bold(20, relativeTo: .title3))
                .foregroundStyle(theme.text)
                .fixedSize(horizontal: false, vertical: true)
            if let clarifier = question.clarifier {
                Text(clarifier)
                    .font(GSFont.body(12, relativeTo: .footnote))
                    .foregroundStyle(theme.neutral700)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: 18)

        HStack(spacing: 10) {
            Button { clearByPreScreen() } label: {
                Text("NOTHING TO FLAG")
                    .font(GSFont.bold(14, relativeTo: .headline))
                    .tracking(0.8)
                    .foregroundStyle(theme.bg)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(GS3DButtonStyle(face: theme.accent, cornerRadius: 15))

            Button {
                withAnimation(.easeOut(duration: 0.18)) { phase = .screening }
            } label: {
                Text("YES, SOMETHING")
                    .font(GSFont.bold(14, relativeTo: .headline))
                    .tracking(0.8)
                    .foregroundStyle(theme.text)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(GS3DButtonStyle(face: theme.raised3DFace,
                                         lip: theme.raised3DLip,
                                         cornerRadius: 15))
        }
        Spacer(minLength: 0)
    }

    /// A clean pre-screen records the seven all-NO answers it stands for,
    /// so the stored screening has the same shape either way.
    private func clearByPreScreen() {
        screening.answers = HealthTriage.clearedByPreScreen()
        withAnimation(.easeOut(duration: 0.18)) { settle() }
    }

    // MARK: Questions

    @ViewBuilder
    private var screeningPhase: some View {
        if index < HealthTriage.questions.count {
            let question = HealthTriage.questions[index]
            VStack(alignment: .leading, spacing: 8) {
                Text("BEFORE WE START")
                    .font(GSFont.bold(10, relativeTo: .caption2))
                    .tracking(1.1)
                    .foregroundStyle(theme.accent)
                Text(question.prompt)
                    .font(GSFont.bold(20, relativeTo: .title3))
                    .foregroundStyle(theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let clarifier = question.clarifier {
                    Text(clarifier)
                        .font(GSFont.body(12, relativeTo: .footnote))
                        .foregroundStyle(theme.neutral700)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .gs3DCard(cornerRadius: 18)

            HStack(spacing: 10) {
                chip("NO", answer: false, question: question)
                chip("YES", answer: true, question: question)
            }
            Text("\(index + 1) OF \(HealthTriage.questions.count)")
                .font(GSFont.bold(10, relativeTo: .caption2))
                .tracking(1.1)
                .foregroundStyle(theme.neutral700)
            Spacer(minLength: 0)
        } else {
            Spacer(minLength: 0)
        }
    }

    private func chip(_ label: String, answer: Bool,
                      question: HealthTriage.Question) -> some View {
        Button { record(question, answer) } label: {
            Text(label)
                .font(GSFont.bold(15, relativeTo: .headline))
                .tracking(1.0)
                .foregroundStyle(answer ? theme.text : theme.bg)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
        .buttonStyle(GS3DButtonStyle(
            face: answer ? theme.raised3DFace : theme.accent,
            lip: answer ? theme.raised3DLip : nil,
            cornerRadius: 15))
    }

    /// Step 2. Same grammar as Step 1 deliberately — this is the same
    /// conversation continuing, not a new interrogation because they
    /// answered "yes" to something.
    @ViewBuilder
    private func followUpPhase(_ followUp: HealthTriage.FollowUp) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ONE MORE THING")
                .font(GSFont.bold(10, relativeTo: .caption2))
                .tracking(1.1)
                .foregroundStyle(theme.accent)
            Text(followUp.prompt)
                .font(GSFont.bold(20, relativeTo: .title3))
                .foregroundStyle(theme.text)
                .fixedSize(horizontal: false, vertical: true)
            if let clarifier = followUp.clarifier {
                Text(clarifier)
                    .font(GSFont.body(12, relativeTo: .footnote))
                    .foregroundStyle(theme.neutral700)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: 18)

        VStack(spacing: 10) {
            ForEach(followUp.options) { option in
                Button { recordFollowUp(followUp, option) } label: {
                    Text(option.label)
                        .font(GSFont.bold(14, relativeTo: .headline))
                        .tracking(0.6)
                        .foregroundStyle(theme.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.gs3DCardStyle(cornerRadius: 15))
            }
        }
        Spacer(minLength: 0)
    }

    /// Coach declining to program. Names the boundary, never implies a
    /// diagnosis, and never leaves the athlete with nothing.
    private func declinedCard(_ outcome: HealthTriage.Outcome) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(copy(for: outcome))
                .font(GSFont.body(14, relativeTo: .body))
                .foregroundStyle(theme.text)
                .fixedSize(horizontal: false, vertical: true)
            // The way back in. A refer-out is not a dead end; it is a
            // conversation Coach asked them to have.
            if case .referOut = outcome {
                Button { clinicianCleared() } label: {
                    Text("MY DOCTOR CLEARED ME")
                        .font(GSFont.bold(14, relativeTo: .headline))
                        .tracking(0.9)
                        .foregroundStyle(theme.bg)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                }
                .buttonStyle(GS3DButtonStyle(face: theme.accent, cornerRadius: 15))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: 18)
    }

    private func copy(for outcome: HealthTriage.Outcome) -> String {
        switch outcome {
        case .referOut(let flagged): return HealthTriage.referralCopy(flagged: flagged)
        case .delay(let reason):     return reason.copy
        default:                     return ""
        }
    }

    // MARK: Flow

    private func start() {
        guard !started else { return }
        started = true
        Task {
            let stored = (try? await HealthScreeningRepository.load()) ?? HealthScreening()
            screening = stored
            let outcome = stored.outcome()

            // ORDER MATTERS, and getting it wrong was a live bypass. A
            // refused athlete has no cleared_at, so `needsScreening` is
            // true for them forever — and this check used to come FIRST,
            // which handed the questions straight back to someone who had
            // just been refused. Answering differently the second time
            // walked through the gate. The comment here claimed a standing
            // flag survived a relaunch; it did not.
            if stored.hasStandingRefusal {
                withAnimation(.easeOut(duration: 0.18)) { phase = .declined(outcome) }
                return
            }
            // Resume a part-finished screening at the question they owe,
            // rather than restarting or refusing.
            if case .incomplete(let next) = outcome {
                withAnimation(.easeOut(duration: 0.18)) { phase = .followUp(next) }
                return
            }
            if stored.answers.isEmpty || stored.needsScreening {
                withAnimation(.easeOut(duration: 0.18)) { phase = .preScreen }
                return
            }
            switch outcome {
            case .cleared:
                onCleared(nil)
            case .clearedWithAdvisory(let text):
                onCleared(text)
            case .referOut, .delay, .incomplete:
                withAnimation(.easeOut(duration: 0.18)) { phase = .declined(outcome) }
            }
        }
    }

    private func record(_ question: HealthTriage.Question, _ answer: Bool) {
        screening.answers[question.id] = answer
        withAnimation(.easeOut(duration: 0.18)) {
            index += 1
            if index >= HealthTriage.questions.count { settle() }
        }
    }

    private func recordFollowUp(_ followUp: HealthTriage.FollowUp,
                                _ option: HealthTriage.FollowUp.Option) {
        screening.followUps[followUp.id] = option.id
        withAnimation(.easeOut(duration: 0.18)) { settle() }
    }

    private func settle() {
        let outcome = screening.outcome()
        switch outcome {
        case .incomplete(let next):
            // More to ask before we know anything. Persist so a kill
            // mid-screening resumes rather than restarting.
            phase = .followUp(next)
            persist()
            return
        case .cleared:
            screening.clearedAt = Date()
            persist()
            onCleared(nil)
        case .clearedWithAdvisory(let text):
            screening.clearedAt = Date()
            persist()
            onCleared(text)
        case .referOut, .delay:
            phase = .declined(outcome)
            persist()
        }
    }

    private func clinicianCleared() {
        screening.clinicianCleared = true
        screening.clearedAt = Date()
        persist()
        onCleared(nil)
    }

    private func persist() {
        let snapshot = screening
        Task {
            guard let userID else { return }
            try? await HealthScreeningRepository.save(snapshot, userID: userID)
        }
    }
}

// MARK: - HealthGateSheet
//
// The wizard's presentation of the gate. A sheet rather than a takeover
// because the five doors are also how an athlete EDITS their profile, and
// editing is not prescribing — they may browse freely. What they may not
// do is have a program written for them unscreened, so the gate stands in
// front of GENERATION, which is the one thing that produces loads.
struct HealthGateSheet: View {
    @Environment(\.gsTheme) private var theme
    let userID: UUID?
    var onCleared: (String?) -> Void

    var body: some View {
        ScrollView {
            HealthGateView(userID: userID, onCleared: onCleared)
                .padding(.horizontal, 16)
                .padding(.top, 20)
        }
        .background(theme.bg)
    }
}
