# Overnight session — 2026-08-26

Written for the owner waking up. Everything below is on `master` at
`a91b0ea` and went out to TestFlight.

---

## The two research verdicts that change plans

Both sweeps were asked to answer a **decision**, not just to gather. Both
came back rejecting the thing they were sent to support. These are the two
findings most likely to change what you thought you wanted built.

### 1. Do NOT cap per-session per-muscle volume

The 17-set bro-split chest day is real. Capping it is the wrong fix.

> The only effect shown to hurt growth is dropping **below 12 weekly sets**
> per muscle. Capping a 17-set chest day at 8 in a once-weekly split turns
> 17 weekly sets — squarely inside the supported 12–20 band — into 8, which
> is the one condition with a demonstrated penalty.

Every candidate cap number fell apart:

| Number | What it actually is |
|---|---|
| 6 | Unpublished analysis, biased by untrained subjects who rarely exceeded 6 |
| 8, 10 | Acute protein-synthesis studies — one of them **in rats** |
| 11 | Meta-analysis its own presenter says was **not controlled for weekly volume**; the threshold is an admitted arbitrary statistical convention |

Two studies once supporting a session limit have been **retracted**. Three
RCTs found stacking neutral or better, including one where ~20 quad sets in
a single session beat a volume-matched split.

**The honest gap:** the central experiment does not exist. Not one study in
175 findings holds weekly volume constant, varies only sets-per-session,
and measures growth. Every per-session number is an acute proxy, an
uncontrolled meta-regression, or a retracted paper.

> **RESOLVED 2026-08-26, and not by any of the options below.** The owner's
> answer was better than the four: *"Everyone responds to volume stimulus
> differently. Let's prescribe middle of the road, and perturb the volume
> every couple of weeks to see how performance improves. The data or the
> client will tell us how it feels."*
>
> So the app no longer picks a number at all — it **searches for each
> athlete's own**, per muscle, inside 12–25. See `VolumeTitration.swift`
> and the recovery probe. Recommendation 1 was already true; 2 and 3 are
> subsumed by the search (which redistributes and holds rather than
> truncating); 4 remains genuinely open.
>
> Two owner corrections shaped it, both now pinned by tests:
> - **0–1 RIR is not a fatigue signal.** Someone who chose
>   `EffortAppetite.toFailure` is *prescribed* 0–1 RIR. My first draft
>   would have permanently deloaded the most committed lifters for
>   training as instructed.
> - **A logged RPE of 7 is not noise.** Discarding every 7 throws away
>   real answers to keep out defaults.
>
> And one design consequence worth knowing: the search **holds** when the
> probe is silent and only **cuts** without it. Silence blocks the climb
> everywhere and the retreat nowhere.

**What the sweep recommended instead**, for the record — the four options
that were on the table before the search replaced them:

1. **Recount before reacting.** Fractional set counting (direct 1.0,
   indirect 0.5) was the best-fitting model. This is *already* what
   `weeklyMuscleSets` does — some of the "17" is indirect.
2. **A soft redistribution advisory at 10 direct-equivalent sets** per
   muscle per session. Try to move the excess to another session that
   trains that muscle. An advisory trigger, never a truncation number.
3. **A hard invariant:** redistribution must never drop weekly per-muscle
   volume below 12 direct-equivalent sets. If a true bro-split cannot
   absorb the excess, leave the 17 and surface a note. *17 weekly sets in
   one session is defensible; 8 weekly sets is not.*
4. **Attack session quality instead** — this is the better-evidenced
   version of the problem. Cap total sets per whole session (~15–25 across
   all muscles), require 2–4 distinct exercises rather than 17 sets of two
   movements, and surface effort guidance. Insufficient effort — 47% of
   lifters leaving 6+ reps in reserve — is the dominant real-world form of
   junk volume.

If a hard block is wanted for UX rather than science, put it well above the
contested band: flag at 20+ direct-equivalent sets, where even the most
permissive meta-analysis has essentially no data.

### 2. Female: a symptom-and-life-stage layer, NOT a cycle-phase engine

- **Do not build phase-based programming.** The effect is absent in the
  best controlled data, the originator of cycle syncing has retracted the
  blanket rules, and phase is not knowable from a calendar — ovulation can
  fall on day 9 or day 19 of identically-long cycles, several cycles a year
  are anovulatory, and an OCP bleed carries no signal. A phase generator
  would ship a confident-looking wrong answer to users who cannot check it.
- **Do build, opt-in:** cycle and symptom logging, a session-feel log, and
  a flag when bleed pattern or cycle length *changes* — genuinely
  meaningful, and the earliest sign of low energy availability. Nothing in
  it should silently alter a program.
- **Perimenopause: the expected answer is wrong.** A 126-study,
  ~4,000-woman meta-analysis finds peri- and postmenopausal women respond
  to training like everyone else, so **no menopause-specific protocol is
  warranted**. What IS supported is life-stage *emphasis*: heavy compound
  loading at 65–85% 1RM because that is what moves bone (light and band
  work does not), explicitly **not** softening load for osteopenia (dose by
  fitness, not T-score), and balance work for a ~23% fall-rate reduction.

---

## What shipped

**Safety**
- The health gate guarded **one of four doors** into the generator. It now
  gates *prescribing* rather than one screen, so every door inherits it —
  and fails closed while the screening is unread.
- **PAR-Q+ Step 2.** One YES no longer refuses forever. Follow-ups ask
  about control, symptoms and current activity — never which condition.
  Cardiac stays terminal deliberately: clearing it needs an intensity
  ceiling we have not built.
- **A bypass**: a refusal handed the questionnaire straight back, and
  answering differently walked through it.
- **Manual clear** in the LIMITS door, recorded as a clinician's clearance
  in its own field rather than as a rewritten answer.
- **The app was chasing pre-layoff numbers for the athlete** — the corpus's
  named failure mode on return, in three places. Fixed with a horizon that
  is intrinsic to the prescription engines rather than a parameter callers
  must remember.

**Correctness**
- The wizard **discarded the consult's equipment answer** (dumbbells-only →
  full-gym program) and the commitment question **recorded a different
  number than it showed you**.
- The volume note could report a week "balanced" that it had broken; it now
  reports what it could not fix.
- The coverage gate counted *effective* sets while its note claimed
  *direct* — novices shipped weeks with zero direct arm work.
- Watch: `setIndex` hardcoded to 1 (which `BlockProgression` sorts by), and
  `bodyWeightLbs` dropped.

**Features**
- **HR in solo**: a *sharing* switch was gating whether you could see your
  own heart rate. Split into `sampleHeartRate` and `shareHeartRate`.
- **Swap during transit** — the one window it was missing from.
- **Accessory variety** as a probed flavour, per your steer.

**Corpus: 1,071 → 1,328 findings across 24 areas.** Five researcher-led
channels added (Huberman, Attia, Sims, Galpin, Patrick); 200 episodes
fetched, 2.35M words.

---

## Limits worth knowing

- **The Watch work is compile-verified only.** I cannot pair a device, so
  the wire path is unproven. Please confirm a solo set logs from the wrist
  before trusting it.
- **Olympic lifting: ~90% of that area is one channel** whose owner has a
  commercial stake, every "study" a secondhand relay, and **zero injury
  data across 81 claims**. The corpus cannot answer "is this safe
  unsupervised" — which is the only question that matters before
  auto-prescribing a snatch. That is why a `source` column now exists.
- **Tempo: do not ship a numeric prescription.** Rep durations 0.5–8s are
  equivalent near failure, concentric tempo is not prescribable at all
  (rep speed decays involuntarily), and there is **zero** direct research
  on intra-rep pauses.
- **Equipment is genuinely thin** — only 25 transcripts in a 6,250-video
  store touch minimal-equipment training. The roster is gym-equipped
  lifting science. Not padded around.

## Still open

- Session SHAPE (recommendation 4): a whole-session set ceiling, and a
  rule requiring 2-4 distinct exercises rather than 17 sets of two
  movements. This is what a 17-set chest day actually violates, and the
  search does not address it. Note the app already trims by
  `sessionMinutes`, and the audit's rule 5 says respect the clock before
  the science — so this may be partly redundant.
- Home ignores the program entirely — `loadTodaysRoutine` hands back the
  last routine used, so the hero repeats one day forever while the block
  advances. Design exists; it was rejected by review on a false invariant
  and an unhandled `repeatWeek`, and needs a revision pass.
- `TrainingProfile.exclusions` still has no production writer.
- RIR is computed on every exercise and dropped at the persistence
  boundary.
