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
                answer: "RPE is how hard the set felt, 5–10, where 10 means nothing left in the tank. Swipe the RPE track when logging a set. It's not just a gym-bro vibe — it's a validated scale (Zourdos 2016) anchored to reps in reserve: RPE 8 means about two reps still in you, RPE 10 means zero. That's why it's worth logging even though it's optional — a hard 5 and an easy 5 leave different reps in the tank, and your weight suggestions sharpen when they know which one you did. Newer lifters read their own reserve less precisely, so don't agonize over the exact number — round the feeling to the nearest point and move on."),
            HelpEntry(
                question: "How do I log a failed set — and why would I?",
                answer: "Flick the RPE track past 10 to FAIL and log the rep you failed on: \"7 + FAIL\" means you attempted a 7th rep and didn't get it — six completed with nothing left. A true failure is the one point every strength formula is anchored to: zero reps in reserve (Zourdos 2016), which makes it the most honest data you can give the app. It recalibrates your estimated max — the Brzycki (1993) and Epley (1985) rep-max equations turn six good reps at a weight into a projected 1RM — counts the completed reps toward your volume, and can even set a PR at the reps you actually finished. Those estimates are sharpest at low reps and get looser past ten (LeSuer 1997), so a failed heavy set tells the app more than a failed light one. Only a missed single carries nothing."),
            HelpEntry(
                question: "Where do weight suggestions come from?",
                answer: "Your own history. The app looks at your last sets, your best work (adjusted by RPE, so a set with reps to spare counts for more — Zourdos 2016), and — when you're new to a lift — your starting-weight anchors, then projects a weight for today's target reps using the reps-to-percent relationship that every lifter's strength roughly follows. Suggestions are a starting point; you're always the final judge of what goes on the bar. Want the actual numbers behind the percentages? See THE SCIENCE section below."),
            HelpEntry(
                question: "How is the workout time estimate calculated?",
                answer: "From your actual prescription: about two minutes per set, plus your rest between sets, plus a transition window between exercises. A tighter routine really does read shorter."),
            HelpEntry(
                question: "How do supersets, burnouts, and failure sets work?",
                answer: "In the routine builder, every exercise has structure chips. LINK SUPERSET pairs an exercise with the next one — in your session the pair alternates with no rest between them and one shared rest after each round. BURNOUT makes the final set an all-out max-rep set (the target reads MAX), and TO FAILURE prescribes the last set to failure — log it with the FAIL flick and the app reads it exactly right. One design note: both of these ride the last set on purpose. Training to failure is the zero-reps-in-reserve anchor (Zourdos 2016), but most productive work is done a rep or two shy of it — so Coach spends the all-out effort at the end of an exercise, not by burning you out on set one."),
            HelpEntry(
                question: "What are the rest recovery hints?",
                answer: "With a heart-rate monitor connected, the app learns how fast YOUR heart rate usually drops during rest. Recover faster than your baseline and it offers GO EARLY; still elevated near the end and it suggests +30s. Hints only — never commands. Why learn your baseline instead of printing a fixed rest time? Because between-set recovery varies a lot from lifter to lifter — women, for instance, tend to regain force faster (Hunter 2014) — so any single hard-coded clock would be wrong for most people. Your own heart rate is a more honest signal than a number we could guess for you."),
        ]),
        HelpSection(title: "THE SCIENCE", entries: [
            HelpEntry(
                question: "Why does 3 days a week give me full-body workouts instead of push/pull/legs?",
                answer: "Because of the frequency law. When weekly sets are held equal, training a muscle at least twice a week beats hitting it once (Schoenfeld, Grgic & Krieger 2019). A three-day push/pull/legs split trains each muscle just once a week; three full-body days train everything three times — same total work, better spread — so at three days a week, Coach builds full-body sessions. Being honest about the size of the effect: it's clearest going from once to twice a week, and the extra benefit past that gets murky once volume is equated. That's why more available days unlock splits (upper/lower around four days, push/pull/legs around six) rather than just piling more frequency onto three. Frequency is a tool for spreading your volume out, not a target to chase for its own sake."),
            HelpEntry(
                question: "Does the app train women differently?",
                answer: "Same movements, same training zones, same rep ranges — and that's a deliberate, evidence-based choice, not an oversight. Relative strength and muscle gains are essentially equal between women and men (Roberts, Nuckols & Krieger 2020); men gain more in absolute terms mostly because they start with more muscle. So there's no basis for women-only weights, women-only exercises, or a separate 'toning' zone. Where real physiological differences exist they're small, and we handle them lightly: women are reliably more fatigue-resistant (Hunter 2014) and tend to get a rep or two more at a given percentage (Hoeger 1990), so suggestions lean on your logged reps, not on a sex field. We do NOT cut women's volume or force shorter rest — that evidence is thin, and the lone trial hinting women plateau on less volume is single and contested, so we keep the standard set landmark. We also don't lock training to menstrual-cycle phase: that research is weak and inconsistent (McNulty 2020). Want to autoregulate around how you feel? That's yours to drive, never a rule we impose."),
            HelpEntry(
                question: "Why won't Coach give me 7 hard days?",
                answer: "Because around the sixth hard day, the math stops paying you back. Muscle recovers fast — protein synthesis is largely finished within 48–72 hours (MacDougall 1995, Phillips 1997) — but tendons, ligaments and joints turn over more slowly and don't reset just because you rotated to a different muscle group (Cook & Purdam 2009). Train hard day after day and fatigue piles up faster than it clears, which is the on-ramp to overreaching (the Meeusen 2013 consensus). So Coach caps you at six straight training days and drops a rest or active-recovery day on the seventh. It also keeps at least 48 hours between heavy spine-loading sessions — back squats and deadlifts — even when the target muscles differ, because there it's the joints and connective tissue that need the gap, not just the muscle. Honestly: nothing proves a full rest day is strictly required if your splits rotate perfectly. The ceiling is part physiology, part hard-won coaching convention — cheap insurance against the injuries and burnout that end far more programs than under-training ever does."),
            HelpEntry(
                question: "What's an active recovery day for?",
                answer: "Not for 'flushing out' anything — let's retire that myth first. Easy cardio does clear blood lactate faster than sitting still (that part is real, and old news), but lactate isn't what makes you sore: next-day soreness is muscle damage, and clearing lactate doesn't touch it. Being straight with you, the evidence that active recovery actually speeds muscle repair or next-day performance is weak-to-null (Van Hooren & Peake 2018). So what is it good for? Gentle circulation, a little mobility and range-of-motion work, staying in the rhythm of training, and dodging rest-day guilt — modest, real benefits, no overclaiming. The one firm rule: an easy day stays easy. Picture 20–40 minutes at a conversational pace, zone 1–2, a walk or an easy bike. Push it into a real workout and you're just adding fatigue that competes with your next lifting session (Wilson 2012), which defeats the point. Coach will slot a light walk and some mobility here — never a scaled-down lifting session. Beat up or short on sleep? Downgrade it to full rest, guilt-free."),
            HelpEntry(
                question: "Where do the weight percentages come from?",
                answer: "From a well-worn relationship between how heavy a load is — as a percent of your one-rep max — and how many reps you can get with it. Average the two classic formulas, Brzycki (1993) and Epley (1985), and you get roughly: 75% of max ≈ 10 reps, 80% ≈ 8, 85% ≈ 6, 90% ≈ 4. Coach uses that curve to turn a rep target into a starting weight. The honest caveat: these are bands, not laws. Prediction gets loose above about ten reps, where the formulas start to disagree (LeSuer 1997), so lighter, higher-rep targets are fuzzier than heavy ones — and trained lifters squeeze out more reps at the same percent than beginners do. That's why the method shifts with experience. New to a lift? You get straightforward percent-based loads and double progression — add reps until you top the range, then add weight. More experienced? Coach leans on RIR (reps in reserve): you autoregulate load by how many reps you left in the tank, which tracks day-to-day readiness better than a fixed percent can (Zourdos 2016, Mann 2010)."),
            HelpEntry(
                question: "Can I lift and do cardio the same day?",
                answer: "Yes — but timing and the type of cardio matter. Endurance work too close to lifting can blunt strength gains; it's called the interference effect, and a big review (Wilson 2012) found it hits power hardest, strength moderately, and muscle growth least. Two practical rules fall out of that. First, separation: if you're doing both in one day, aim for six or more hours between them — that preserves your lifting adaptations nearly as well as splitting them across days, while back-to-back is worse (Robineau 2016). Can't get six hours? Lift first while you're fresh, then keep the cardio short and easy. Second, modality near leg days: running competes with squats and deadlifts more than cycling does, probably because the pounding overlaps with the same eccentric muscle damage — so Coach steers running away from heavy leg days and reaches for the bike or rower instead. One honest note: most interference research used hard, high-volume endurance work. For a recreational lifter doing a moderate 20–30 minutes, the real-world hit is probably smaller than the averages suggest — so don't panic over a little cardio."),
            HelpEntry(
                question: "How hard should my sets be — do I train to failure?",
                answer: "Close, not always all the way — and it depends on the lift. On big compound lifts (squats, deadlifts, presses), stop 1–3 reps short of failure most of the time: the last grinding rep adds a lot of fatigue and joint stress for little extra stimulus, and the field's coaches keep heavy accessories at 2–3 reps in reserve for the same reason. On small isolation lifts (curls, raises, pushdowns), going to failure now and then is fine and sometimes useful — the loads are light, the fatigue cost is low, and isolation is the one place a true max-effort set is cheap. That's why the app's RPE track matters: logging honest effort is how Coach knows whether a stall is a strength problem or a fatigue problem. One caution from the coaches: chasing rep maxes on accessory lifts (a 3-rep-max pushdown, say) is how elbows get hurt — save max attempts for the lifts built to hold them."),
            HelpEntry(
                question: "Do I really need isolation exercises, or are compounds enough?",
                answer: "You need both, and here's the honest anatomy of why. Compounds are the backbone — most of your volume should come from them — but several muscles literally cannot be trained well by any compound lift. Hamstrings barely grow from squats (hip and knee actions cancel each other out — a 10-week trial confirmed it). The long head of your triceps gets shortchanged by pressing. Side delts and calves have no compound that meaningfully trains them at all. So isolation work isn't fluff; it's coverage for the muscles compounds miss, plus targeted work for weak points that hold your big lifts back — direct triceps work genuinely helps a stuck bench lockout. That's why Coach's programs put compounds first and add isolation where the anatomy demands it, even on strength-focused days."),
            HelpEntry(
                question: "I've stalled. What actually breaks a plateau?",
                answer: "First, the honest question: is it a strength plateau or a fatigue plateau? They look identical in the logbook and have opposite fixes. If your reps are grinding (RPE 8.5+) and everything feels heavy, you're carrying fatigue — the fix is a deload (a lighter week), not more effort, and Coach will propose one rather than impose it. If you're fresh, sleeping fine, and the bar still won't move, you've likely maxed what your current muscle and technique can express — the field's answer is a hypertrophy block: shift toward more volume and accessory work for a few weeks to build the muscle, then return to heavy work with more raw material. And if your training has been sparse — big gaps between sessions of a lift — the fix is simply more frequency before anything fancier. Coach's stall detection walks exactly this differential before it suggests anything."),
            HelpEntry(
                question: "Should I train differently as I get older?",
                answer: "Train the same movements — recover with more respect. Nothing about age changes what makes muscle grow; lifters in their 50s, 60s and beyond build muscle and strength with the same training that works at 25, and resistance training is one of the best-evidenced things you can do for aging well: it maintains bone density (which is why Coach weights bone-supporting, spine-loading work higher when that goal is ranked), preserves the fast-twitch muscle that guards balance and independence, and protects joints by strengthening what surrounds them. What does change: recovery takes longer, so hard sessions want more space between them; warmups earn their keep; and joint-friendly variations (trap-bar instead of straight-bar, machines where a joint complains) are smart trades, not surrender. Set your age in Coach's BODY section and it shapes these defaults — it never gates what you're allowed to do."),
            HelpEntry(
                question: "Do I need ab work, or do squats cover my core?",
                answer: "Squats and deadlifts brace your core hard — but bracing is isometric, and muscle grows from lengthening and shortening under load. When we read the research channels on this, the consensus was clear: if you want your midsection stronger (or visible), it needs direct work, and the direct work should be loaded flexion — cable crunches, hanging leg raises, ab-wheel rollouts — not endless planks (no movement, no growth stimulus) and not weighted twists (obliques grow like any muscle, and a thicker waist is rarely the goal). Two to four short doses a week, 10–15 controlled reps, is the field's dose. That's exactly why Coach slots a core exercise on your lower and leg days and picks loaded movements over planks when your goals are physique-flavored."),
            HelpEntry(
                question: "Something hurts. Train through it or stop?",
                answer: "Neither, usually — train around it. First, sort soreness from pain: soreness is diffuse, in the muscle belly, worst a day or two after novelty, and warms up better as you move. Pain is sharp, near a joint or tendon, often on specific reps, and gets worse as you go. Soreness is fine to train through. Pain is information — and the answer is almost never bed rest, because complete rest detrains the exact tissue you need strong. The field's playbook: drop the movement that provokes it, keep training everything that doesn't hurt, and come back to the provoking pattern gradually — lighter loads, friendlier variations, pain kept to a mild whisper rather than a shout. In Coach, mark an exercise as a no-go with the injury reason and it excludes the movement family and goes cautious on that joint — softly, without leaving holes in your program. Pain that's severe, worsening, or hanging around for weeks is a professional's job, not an app's."),
            HelpEntry(
                question: "What should training look like for fat loss?",
                answer: "Lift like you're keeping the muscle — because that's the job. The deficit does the fat loss; training's role is telling your body the muscle stays. That means keeping weights heavy-ish and effort real rather than switching to light 'toning' circuits — muscle you don't use in a deficit is muscle you lose. Coach's weight-loss programs bias big compound lifts (the most work per minute you can buy) and add zone-2 cardio as a calorie tool, not a punishment. Expect strength to plateau or dip a little in a deficit; that's arithmetic, not failure. Two honest notes from the research crowd: protein matters more in a deficit than any exercise choice (aim around 1g per pound of target bodyweight), and the scale is a liar week-to-week — the body-weight trend in your Stats page smooths it into something worth reacting to."),
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
                answer: "Beating your best weight for at least that many reps — so a heavy single and a hard set of ten are separate achievements. They really are different lifts: the reps-to-weight relationship isn't linear (Brzycki 1993, Epley 1985), so your ten-rep max and your one-rep max sit at different points on your strength curve, and each earns its own record. Bodyweight exercises set rep records instead. A failed set can still be a record at the reps you completed."),
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
