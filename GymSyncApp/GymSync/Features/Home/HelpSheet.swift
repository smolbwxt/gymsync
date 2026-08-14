import SwiftUI

// MARK: - HelpSheet
//
// The "?" FAQ (owner 2026-08-14: "the anti-onboarding" — help at the
// moment of confusion instead of a front-loaded data dump). Curated from
// the questions lifters actually ask (Hevy's help-center taxonomy was the
// reference) plus the GymSync-only features no competitor FAQ covers:
// crews, turns, the soundboard, hubs, and the failure doctrine.
//
// Static content on purpose for v1 — shipping copy beats a CMS. The
// interactive spotlight TOURS (guided walk-throughs continuing past the
// solo-workout widget) are the follow-up round; entries here describe
// steps in words.
struct HelpSheet: View {
    @Environment(\.gsTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var expandedID: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Self.sections) { section in
                        Text(section.title)
                            .font(GSFont.bold(12, relativeTo: .caption2))
                            .tracking(0.8)
                            .foregroundStyle(theme.text.opacity(0.6))
                            .padding(.horizontal, 16)
                            .padding(.top, 22)
                            .padding(.bottom, 8)

                        VStack(spacing: 0) {
                            ForEach(section.entries) { entry in
                                entryRow(entry)
                                if entry.id != section.entries.last?.id {
                                    GSDivider().padding(.horizontal, 14)
                                }
                            }
                        }
                        .gs3DCard(cornerRadius: GSMetrics.radiusMd)
                        .padding(.horizontal, 16)
                    }
                    Spacer(minLength: 32)
                }
            }
            .background(theme.bg)
            .navigationTitle("How do I…?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(GSFont.bold(15, relativeTo: .body))
                        .tint(theme.accent)
                }
            }
        }
    }

    // Expandable Q/A row — flat furniture inside the section's extruded
    // card (the settings-list idiom: extruding every row would be noise).
    @ViewBuilder
    private func entryRow(_ entry: HelpEntry) -> some View {
        let isOpen = expandedID == entry.id
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    expandedID = isOpen ? nil : entry.id
                }
            } label: {
                HStack(spacing: 10) {
                    Text(entry.question)
                        .font(GSFont.bold(14, relativeTo: .headline))
                        .foregroundStyle(theme.text)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.neutral500)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                Text(entry.answer)
                    .font(GSFont.body(13.5, relativeTo: .subheadline))
                    .foregroundStyle(theme.neutral700)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            }
        }
    }

    // MARK: - Content

    struct HelpSection: Identifiable {
        let title: String
        let entries: [HelpEntry]
        var id: String { title }
    }

    struct HelpEntry: Identifiable {
        let question: String
        let answer: String
        var id: String { question }
    }

    static let sections: [HelpSection] = [
        HelpSection(title: "GETTING STARTED", entries: [
            HelpEntry(
                question: "How do I work out with other people?",
                answer: "Go to the Crews tab and start a crew (+ New Crew) or get added to one by a friend. Open your crew's room and hit Start Session — everyone joins from their phone, you take turns on the bar, and each lifter logs their sets on their turn. You can swipe the session down to peek at the rest of the app; the REJOIN bar brings you right back."),
            HelpEntry(
                question: "How do I build a routine?",
                answer: "You tab → ROUTINES. You have five slots — tap an open one to build a routine from the exercise catalog: pick exercises, set your target sets, reps, and rest. Tap a filled slot to view, edit, or start it."),
            HelpEntry(
                question: "What does the calendar on Home show?",
                answer: "Everything on your books — solo sessions you've scheduled and crew sessions anyone in your crew has put on the schedule. Tap a day to see it, or use the schedule widget to book a lift. Group sessions can repeat weekly on the days you choose."),
            HelpEntry(
                question: "How do streaks work?",
                answer: "Train in a week and the week counts; string weeks together and the streak grows. Your crew's week streak is the gold number in the crew room — it's the one number the whole crew defends together."),
        ]),
        HelpSection(title: "TRAINING", entries: [
            HelpEntry(
                question: "What is RPE and how do I log it?",
                answer: "RPE is how hard the set felt, 5–10, where 10 means nothing left in the tank. Swipe the RPE track when logging a set. It's optional — but it makes your weight suggestions smarter, because a hard 5 and an easy 5 are different signals."),
            HelpEntry(
                question: "How do I log a failed set — and why would I?",
                answer: "Flick the RPE track past 10 to FAIL and log the rep you failed on: \"7 + FAIL\" means you attempted a 7th rep and didn't get it — six completed with nothing left. That's the most honest data you can give the app: it recalibrates your estimated max, counts the completed reps toward your volume, and can even set a PR at the reps you actually finished. Only a missed single carries nothing."),
            HelpEntry(
                question: "Where do weight suggestions come from?",
                answer: "Your own history. The app looks at your last sets, your best work (adjusted by RPE), and — when you're new to a lift — your starting-weight anchors, then projects a weight for today's target reps. Suggestions are a starting point; you're always the final judge of what goes on the bar."),
            HelpEntry(
                question: "How is the workout time estimate calculated?",
                answer: "From your actual prescription: about two minutes per set, plus your rest between sets, plus a transition window between exercises. A tighter routine really does read shorter."),
            HelpEntry(
                question: "How do supersets, burnouts, and failure sets work?",
                answer: "In the routine builder, every exercise has structure chips. LINK SUPERSET pairs an exercise with the next one — in your session the pair alternates with no rest between them and one shared rest after each round. BURNOUT makes the final set an all-out max-rep set (the target reads MAX), and TO FAILURE prescribes the last set to failure — log it with the FAIL flick and the app reads it exactly right."),
            HelpEntry(
                question: "What are the rest recovery hints?",
                answer: "With a heart-rate monitor connected, the app learns how fast YOUR heart rate usually drops during rest. Recover faster than your baseline and it offers GO EARLY; still elevated near the end and it suggests +30s. Hints only — never commands."),
        ]),
        HelpSection(title: "TRAINING TOGETHER", entries: [
            HelpEntry(
                question: "What's the difference between friends and crews?",
                answer: "Friends see your pump checks and feed activity. A crew is who you actually train with — shared live sessions, chat, a schedule, and the week streak you defend together."),
            HelpEntry(
                question: "How do turns work in a live session?",
                answer: "The rotation moves around the crew: on your turn you lift and log your set, then the next lifter is up. Between exercises there's a TRANSIT window to strip the bar and move stations. Spectating? You can watch the current lifter, throw sounds, and see live heart rates."),
            HelpEntry(
                question: "What's the soundboard?",
                answer: "Your hype arsenal. During a crew session, throw sounds from your Rack at the lifter on the bar. Sounds play through the silent switch (like your music does) and layer over whatever's playing. Manage your Rack from the You tab — it rotates weekly."),
            HelpEntry(
                question: "Can other people see my heart rate?",
                answer: "Only your crew, only during a live session you're both in, and only when you've connected a monitor and turned sharing on. It's never shown anywhere else."),
            HelpEntry(
                question: "What are Local hubs?",
                answer: "Your gym's page. Check in when you're there (the app confirms by location) to see who else from GymSync is around — if they've chosen to be visible. Hubs are 18+ and your visibility is always opt-in."),
        ]),
        HelpSection(title: "RECORDS, DATA & ACCOUNT", entries: [
            HelpEntry(
                question: "What counts as a PR?",
                answer: "Beating your best weight for at least that many reps — so a heavy single and a hard set of ten are separate achievements. Bodyweight exercises set rep records instead. A failed set can still be a record at the reps you completed."),
            HelpEntry(
                question: "Who can see my workouts?",
                answer: "Solo workouts are yours; there's a privacy toggle in Settings that controls whether they appear to friends. Crew sessions are shared with that crew. Hub presence is visible only when you've turned hub visibility on."),
            HelpEntry(
                question: "What happens if I get a new phone?",
                answer: "Everything lives in your account, not the device. Sign in with Apple on the new phone and your history, routines, records, and crews are all there."),
            HelpEntry(
                question: "How do I switch pounds and kilos, or change the look?",
                answer: "You tab → Settings: Units switches lbs/kg everywhere, and Appearance changes the theme and accent color the whole app (soundboard included) wears."),
        ]),
    ]
}
