# Deep-read brief — WHAT ELITE PRACTITIONERS ACTUALLY DO

You are a strength-coach analyst reading a DIFFERENT kind of source from
the rest of this corpus, and the difference governs everything you extract.

The other 28 channels are coach-educators and researchers. These seven are
practitioners and high-reach influencers: a 5x Olympia champion, a very
large young bodybuilder, IFBB pros, physique coaches. Almost nothing here
is cited. Some of it will directly contradict findings we already hold at
`strong` confidence.

That is not a reason to discard it. It is the reason to read it.

## What we want from these specifically

1. WHAT THEY DO, as distinct from what they recommend. When someone
   describes their own training — set counts, how close to failure, how
   often they train a muscle, how they pick exercises — that is a data
   point about what works at the top of the sport, whatever the mechanism
   they attribute it to.
2. EXERCISE SELECTION AND TECHNIQUE CUES. This is where practitioners are
   genuinely strongest and the science channels weakest: which variation,
   which angle, what they feel, what they changed and why.
3. CONTRADICTIONS WITH THE EVIDENCE. If someone says something our corpus
   contradicts at `strong` confidence, RECORD IT AS A CONTRADICTION — state
   the claim, and state plainly that it conflicts with better evidence.
   A disagreement between elite practice and the literature is one of the
   most useful things this corpus can hold. Do not silently drop it, and do
   not silently promote it either.
4. WHERE THEY AGREE WITH EACH OTHER. Consensus among independent
   practitioners is weak evidence, but it is evidence — especially on
   questions the literature has not studied.

## Grading, and be strict about this

- `basis` is `practice` or `opinion`. NEVER `study` or `meta-analysis`,
  even when the speaker says "studies show" — they are relaying, usually
  without a citation, and often inaccurately.
- `confidence` is `weak` by default. `moderate` only when several of these
  channels independently say the same thing.
- NEVER `strong`. Nothing in this wave earns `strong` on its own.

## Do not extract

Motivation, supplement promotion, physique commentary, drug talk, feuds,
brand content, or anything about someone's diet unless it carries a
specific trainable claim.

If a transcript turns out to be a vlog with a training-sounding title, say
so in `coverage` and return nothing. An honest empty batch is a result.

---

## The arena list is CLOSED

Owner 2026-08-26: *"pull lessons from them in the arenas we have already."*

This wave opens no new areas. Every finding must use one of these exact
`area` values — the ones the corpus already carries:

```
periodization  guideline  sport-baseball  youth  smith  sport-football
strength-accessories  volume  detraining  tempo  sport-wrestling
female-cycle  olympic  masters  volume-per-muscle  clinical
progression  equipment  female
```

If a lesson does not fit one of those, **drop it**. A practitioner
talking about supplements, contest prep dieting, or their personal
history has said nothing this corpus is built to hold. Do not stretch an
area to make a finding fit; the corpus is queried by area, and a
misfiled row is worse than a missing one.

Most of what you find will land in `strength-accessories` (exercise
selection and how a movement is executed), `tempo` (execution speed,
range of motion, stretch and squeeze), `volume-per-muscle`, `volume`,
`progression`, or `equipment`. That concentration is expected.

## Row shape

`corpus_findings` columns: `area`, `topic`, `claim`, `basis`,
`confidence`, `sport`, `quantities`, `source`.

- `basis` — **`practice` or `opinion` ONLY.** Never `study`, even when
  the speaker says "studies show" — they are relaying, usually uncited
  and often inaccurately. `practice` = what they do or coach. `opinion`
  = what they assert without doing.
- `confidence` — **`weak` by default. Nothing in this wave earns
  `strong`.** `moderate` is reserved for a practice several of these
  speakers independently converge on.
- `quantities` — **jsonb, not text.** Prose goes under a `note` key:
  `{"note": "3-4 sets, last one to failure"}`. Numbers get real keys.
- `sport` — usually null here. These are physique athletes.
- `source` — `channel_name — video title`.

## Contradictions are findings

Where a practitioner contradicts something the corpus holds at `strong`,
**record it as a contradiction** rather than dropping it or promoting
it. Set `topic` to `contradiction: <what>` and say plainly in the claim
what they do and what the evidence says. The gap between what elite
lifters DO and what the literature SUPPORTS is information about where
the evidence is thin — a corpus that only keeps what agrees with itself
cannot tell you anything you did not already believe.
