import SwiftUI

// MARK: - CoachConsultView
//
// The consult (owner 2026-08-25: "the five doors give coarse adjustment,
// consult confirms, probes, and fine tunes"). One question on screen, the
// next one chosen by ConsultProbe.next(in:) from what is now known.
//
// The design grammar this page obeys, from the review rounds:
//   • Extruded means tappable. Every chip and both nav buttons are
//     GS3DCardStyle/GS3DButtonStyle (press-sink); the question card is
//     .gs3DCard() (no travel), so nothing inert looks pressable.
//   • Widget-scale headers. The question is the biggest thing on screen.
//   • One descriptive line, maximum — the clarifier, and only where the
//     bank supplies one.
//   • Numbers are READ, never improvised: the progress readout comes from
//     ConsultProbe.remaining(in:) and the question's own numbers come
//     from ConsultProbe.ask(_:in:).
//
// This view COLLECTS. ConsultAnswers applies — see that file for why the
// two are apart.
struct CoachConsultView: View {
    @Environment(\.gsTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    /// What the five doors already established.
    let profile: TrainingProfile
    /// The catalog, so constraint chips offer labels selection recognises.
    let catalog: [Exercise]
    /// Log-derived facts. The consult never asks for what it can read.
    let hasLog: Bool
    let loggedDaysPerWeek: Double?
    /// Days the program needs — fills the commitment question's number.
    let recommendedDaysPerWeek: Int?

    /// Needed to persist the health screening. Optional because a signed
    /// -out state must still be able to READ the consult; it just cannot
    /// record anything.
    let userID: UUID?

    var onFinish: (ConsultAnswers) -> Void

    @State private var context = ConsultProbe.Context()
    @State private var answers = ConsultAnswers()
    @State private var selection: Set<String> = []
    @State private var freeText = ""
    /// Snapshots for the back button — the consult is a branching walk,
    /// so stepping back must restore what was known THEN, not recompute
    /// it from a context that has already moved on.
    @State private var history: [Step] = []
    @State private var started = false

    // The health gate. HealthTriage could already refuse to program;
    // until now nothing called it, so a post-cardiac-event athlete walked
    // straight into a loading prescription. It runs BEFORE the opener,
    // because "what is this block chasing" is the wrong first question
    // for someone who should be seeing a doctor.
    @State private var phase: Phase = .loading
    @State private var screening = HealthScreening()
    @State private var screeningIndex = 0
    @State private var advisory: String?

    private enum Phase: Equatable {
        case loading
        case screening
        /// Coach does not program, and says why.
        case declined(HealthTriage.Outcome)
        case probing
    }

    private struct Step {
        let context: ConsultProbe.Context
        let answers: ConsultAnswers
    }

    private var probe: ConsultProbe.Probe? { ConsultProbe.next(in: context) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            switch phase {
            case .loading:
                Spacer(minLength: 0)
            case .screening:
                screeningPhase
            case .declined(let outcome):
                declinedCard(outcome)
                Spacer(minLength: 0)
            case .probing:
                if let advisory {
                    advisoryCard(advisory)
                }
                if let probe {
                    questionCard(probe)
                    answerArea(probe)
                    Spacer(minLength: 0)
                    footer(probe)
                } else {
                    finishedCard
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.bg)
        .onAppear(perform: start)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Button { back() } label: {
                Image(systemName: "chevron.left")
                    .font(GSFont.bold(15, relativeTo: .headline))
                    .foregroundStyle(theme.text)
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(GS3DButtonStyle(face: theme.raised3DFace,
                                         lip: theme.raised3DLip,
                                         cornerRadius: 13, lipHeight: 5))
            .accessibilityLabel(history.isEmpty ? "Close" : "Previous question")

            Text("THE CONSULT")
                .font(GSFont.bold(20, relativeTo: .title3))
                .tracking(0.4)
                .foregroundStyle(theme.text)
            Spacer()
            // Honest progress: what is LEFT, not a fraction of a budget
            // the consult does not have.
            if phase == .probing, probe != nil {
                Text(remainingText)
                    .font(GSFont.bold(10, relativeTo: .caption2))
                    .tracking(1.1)
                    .foregroundStyle(theme.neutral700)
            }
        }
    }

    /// "3 LEFT" once the count is small enough to be a promise, "A FEW
    /// LEFT" while it is still a guess. Saying "9 LEFT" and then asking
    /// four questions would be a number we did not keep.
    private var remainingText: String {
        let left = ConsultProbe.remaining(in: context)
        switch left {
        case 0:     return "LAST ONE"
        case 1...4: return "\(left) LEFT"
        default:    return "A FEW LEFT"
        }
    }

    // MARK: Question

    private func questionCard(_ probe: ConsultProbe.Probe) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ConsultProbe.ask(probe, in: context))
                .font(GSFont.bold(22, relativeTo: .title2))
                .foregroundStyle(theme.text)
                .fixedSize(horizontal: false, vertical: true)
            if let clarifier = probe.clarifier {
                Text(clarifier)
                    .font(GSFont.body(12, relativeTo: .footnote))
                    .foregroundStyle(theme.neutral700)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: 18)
    }

    // MARK: Answers

    @ViewBuilder
    private func answerArea(_ probe: ConsultProbe.Probe) -> some View {
        let options = ConsultVocabulary.options(for: probe, catalog: catalog)
        if options.isEmpty {
            freeTextField(probe)
        } else {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(options) { option in
                        optionChip(option, probe: probe)
                    }
                }
                .padding(.top, 2)
                .padding(.bottom, 6)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func optionChip(_ option: ConsultProbe.Option,
                            probe: ConsultProbe.Probe) -> some View {
        let multi = ConsultVocabulary.isMultiSelect(probe.id)
        let picked = selection.contains(option.id)
        return Button {
            if multi {
                if picked { selection.remove(option.id) } else { selection.insert(option.id) }
            } else {
                answer(probe, [option.id])
            }
        } label: {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(option.label)
                        .font(GSFont.bold(15, relativeTo: .headline))
                        .tracking(0.3)
                        .foregroundStyle(picked ? theme.bg : theme.text)
                        .multilineTextAlignment(.leading)
                    if let detail = option.detail {
                        Text(detail)
                            .font(GSFont.body(11, relativeTo: .caption))
                            .foregroundStyle(picked ? theme.bg.opacity(0.75) : theme.neutral700)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
                if multi {
                    Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                        .font(GSFont.bold(16, relativeTo: .headline))
                        .foregroundStyle(picked ? theme.bg : theme.neutral700)
                }
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: 15,
                                    face: picked ? theme.accent : nil))
    }

    private func freeTextField(_ probe: ConsultProbe.Probe) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(ConsultVocabulary.placeholder(for: probe.id), text: $freeText,
                      axis: .vertical)
                .font(GSFont.body(15, relativeTo: .body))
                .foregroundStyle(theme.text)
                .textInputAutocapitalization(.never)
                .lineLimit(1...4)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .gs3DCard(cornerRadius: 15)
            Spacer(minLength: 0)
        }
    }

    // MARK: Footer

    @ViewBuilder
    private func footer(_ probe: ConsultProbe.Probe) -> some View {
        let options = ConsultVocabulary.options(for: probe, catalog: catalog)
        let multi = ConsultVocabulary.isMultiSelect(probe.id)
        // A single-choice chip IS the commit, so it needs no button. Only
        // free text and multi-select do.
        if options.isEmpty || multi {
            HStack(spacing: 10) {
                Button { skip(probe) } label: {
                    Text("SKIP")
                        .font(GSFont.bold(13, relativeTo: .subheadline))
                        .tracking(0.8)
                        .foregroundStyle(theme.text)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                }
                .buttonStyle(GS3DButtonStyle(face: theme.raised3DFace,
                                             lip: theme.raised3DLip,
                                             cornerRadius: 14))
                Button { commit(probe) } label: {
                    Text(multi && selection.isEmpty ? "NONE OF THESE" : "NEXT")
                        .font(GSFont.bold(14, relativeTo: .headline))
                        .tracking(0.9)
                        .foregroundStyle(theme.bg)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                }
                .buttonStyle(GS3DButtonStyle(face: theme.accent, cornerRadius: 14))
                .disabled(options.isEmpty && freeText.trimmingCharacters(
                    in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var finishedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("THAT'S EVERYTHING I NEED")
                .font(GSFont.bold(22, relativeTo: .title2))
                .foregroundStyle(theme.text)
            Text("Nothing else you could tell me would change what I build.")
                .font(GSFont.body(12, relativeTo: .footnote))
                .foregroundStyle(theme.neutral700)
            Button { onFinish(answers) } label: {
                Text("BUILD IT")
                    .font(GSFont.bold(15, relativeTo: .headline))
                    .tracking(1.0)
                    .foregroundStyle(theme.bg)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(GS3DButtonStyle(face: theme.accent, cornerRadius: 16))
            .padding(.top, 4)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: 18)
    }

    // MARK: The health gate

    @ViewBuilder
    private var screeningPhase: some View {
        if screeningIndex < HealthTriage.questions.count {
            let question = HealthTriage.questions[screeningIndex]
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
                healthChip("NO", answer: false, question: question)
                healthChip("YES", answer: true, question: question)
            }
            Text("\(screeningIndex + 1) OF \(HealthTriage.questions.count)")
                .font(GSFont.bold(10, relativeTo: .caption2))
                .tracking(1.1)
                .foregroundStyle(theme.neutral700)
            Spacer(minLength: 0)
        } else {
            Spacer(minLength: 0)
        }
    }

    private func healthChip(_ label: String, answer: Bool,
                            question: HealthTriage.Question) -> some View {
        Button { answerHealth(question, answer) } label: {
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

    /// Pregnancy and postpartum land here: Coach programs AND says
    /// something, rather than withdrawing the program.
    private func advisoryCard(_ text: String) -> some View {
        Text(text)
            .font(GSFont.body(12, relativeTo: .footnote))
            .foregroundStyle(theme.text)
            .fixedSize(horizontal: false, vertical: true)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface)
            .overlay(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(theme.accent.opacity(0.4), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func answerHealth(_ question: HealthTriage.Question, _ answer: Bool) {
        screening.answers[question.id] = answer
        withAnimation(.easeOut(duration: 0.18)) {
            screeningIndex += 1
            if screeningIndex >= HealthTriage.questions.count { settleScreening() }
        }
    }

    private func settleScreening() {
        let outcome = screening.outcome()
        switch outcome {
        case .cleared:
            screening.clearedAt = Date()
            phase = .probing
        case .clearedWithAdvisory(let text):
            screening.clearedAt = Date()
            advisory = text
            phase = .probing
        case .referOut, .delay:
            phase = .declined(outcome)
        }
        persistScreening()
    }

    private func clinicianCleared() {
        screening.clinicianCleared = true
        screening.clearedAt = Date()
        withAnimation(.easeOut(duration: 0.18)) { phase = .probing }
        persistScreening()
    }

    private func persistScreening() {
        let snapshot = screening
        Task {
            guard let userID else { return }
            try? await HealthScreeningRepository.save(snapshot, userID: userID)
        }
    }

    // MARK: Flow

    /// Seed the context from what is already known. Everything here is
    /// READ — the consult opens already knowing the athlete, which is the
    /// difference between a consult and a form.
    private func start() {
        guard !started else { return }
        started = true
        Task {
            let stored = (try? await HealthScreeningRepository.load()) ?? HealthScreening()
            screening = stored
            let outcome = stored.outcome()
            withAnimation(.easeOut(duration: 0.18)) {
                if stored.needsScreening {
                    phase = .screening
                } else {
                    switch outcome {
                    case .cleared:
                        phase = .probing
                    case .clearedWithAdvisory(let text):
                        advisory = text
                        phase = .probing
                    case .referOut, .delay:
                        // A standing flag survives a relaunch: Coach does
                        // not forget what it was told.
                        phase = .declined(outcome)
                    }
                }
            }
        }
        var seeded = ConsultProbe.Context()
        seeded.hasLog = hasLog
        seeded.loggedDaysPerWeek = loggedDaysPerWeek
        seeded.provenance = profile.provenance
        seeded.equipmentKnown = profile.equipment?.isEmpty == false
        seeded.sessionMinutesKnown = profile.sessionMinutes != nil
        seeded.cautionsKnown = !profile.cautionJoints.isEmpty
        seeded.recommendedDaysPerWeek = recommendedDaysPerWeek
        // daysPerWeek always carries a value (it defaults), so only a
        // STATED one counts as known — otherwise the consult would never
        // ask the single highest-gain question in the bank.
        if profile.provenance["daysPerWeek"] == .stated
            || profile.provenance["daysPerWeek"] == .confirmed {
            seeded.statedDaysPerWeek = profile.daysPerWeek
        }
        context = seeded
    }

    private func commit(_ probe: ConsultProbe.Probe) {
        if ConsultVocabulary.isMultiSelect(probe.id) {
            answer(probe, Array(selection).sorted())
        } else if probe.id == "anchor_lifts" {
            answer(probe, ConsultVocabulary.parseAnchors(freeText))
        } else {
            let text = freeText.trimmingCharacters(in: .whitespacesAndNewlines)
            answer(probe, text.isEmpty ? [] : [text])
        }
    }

    /// Skipping records that we ASKED, so the probe does not come back,
    /// but writes no value — the field keeps whatever the doors set. A
    /// question the athlete declined is not an answer of "none".
    private func skip(_ probe: ConsultProbe.Probe) {
        history.append(Step(context: context, answers: answers))
        var next = context
        next.answered.insert(probe.id)
        advance(to: next)
    }

    private func answer(_ probe: ConsultProbe.Probe, _ values: [String]) {
        history.append(Step(context: context, answers: answers))
        var next = context
        next.answered.insert(probe.id)
        var recorded = values

        switch probe.id {
        case "opener":
            next.goalBranch = values.first
        case "days":
            let days = values.first.flatMap { Int($0) }
            next.statedDaysPerWeek = days
            // The commitment question's number is the cadence they just
            // ASKED for — "the work will take N days a week" is only true
            // if N is the number they chose, not one we picked.
            next.recommendedDaysPerWeek = days ?? next.recommendedDaysPerWeek
        case "commitment":
            // Store the number the athlete was SHOWN alongside their
            // choice, so what we write is what they agreed to.
            if values.first == "commit", let days = recommendedDaysPerWeek {
                recorded = ["commit", "\(days)"]
                next.statedDaysPerWeek = days
            }
        case "equipment":       next.equipmentKnown = true
        case "session_length":  next.sessionMinutesKnown = true
        case "cautions":        next.cautionsKnown = true
        case "standing_rule":   next.offeredRuleCapture = true
        default: break
        }
        if !recorded.isEmpty {
            answers.record(probe.id, recorded)
            for key in probe.tunes { next.provenance[key] = .stated }
        } else if ConsultVocabulary.isMultiSelect(probe.id) {
            // "None of these" IS an answer for a closed multi-select —
            // see ConsultAnswers' comfort handling.
            answers.record(probe.id, [])
            for key in probe.tunes { next.provenance[key] = .stated }
        }
        advance(to: next)
    }

    private func advance(to next: ConsultProbe.Context) {
        selection = []
        freeText = ""
        withAnimation(.easeOut(duration: 0.18)) { context = next }
    }

    private func back() {
        guard let previous = history.popLast() else { dismiss(); return }
        selection = []
        freeText = ""
        withAnimation(.easeOut(duration: 0.18)) {
            context = previous.context
            answers = previous.answers
        }
    }
}
