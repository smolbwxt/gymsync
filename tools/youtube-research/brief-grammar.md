# Brief: the GRAMMAR of a training instruction

You are not collecting claims. Every previous wave did that, and the
corpus already holds 2,251 of them. This one collects **shapes**.

## The question

An athlete types a rule into the app in their own words. Coach has to
recognise what KIND of instruction it is before it can act on one. Right
now the list of kinds it recognises is:

```
PAIR <exercise>            do this alongside every lift
AVOID <exercise>           never include this
ORDER <muscle> <muscle>    train the first before the second
LIGHT <day>                keep that day easy
```

**That list was invented from four examples.** Nobody checked it against
how instructions are actually phrased. If real coaching language is
dominated by shapes that list has no slot for, then every athlete who
phrases a rule that way is silently told "I could not build that" —
forever, and with no way to discover why.

Your job is to find out what the real shapes are.

## What to extract

For every durable, imperative instruction in your transcripts, record its
**template** — not what it claims, but how it is built.

```json
{
  "grammar": "cap(metric, number)",
  "verbatim": "don't go past about twenty sets a week for any muscle",
  "slots": {"metric": "weekly sets per muscle", "number": "20"},
  "slot_types": ["metric", "number"],
  "scope": "per_muscle",
  "source": "<channel_name> — <video title>"
}
```

- `grammar` — a short lowercase predicate with typed slots, e.g.
  `avoid(exercise)`, `pair(exercise, scope)`, `order(muscle, muscle)`,
  `cap(metric, number)`, `swap(exercise, exercise, condition)`,
  `bookend(position, exercise)`, `conditional(observation, action)`.
  **Invent the predicate you need.** Do not force an instruction into one
  of the four above — the whole point is to discover the ones missing.
- `verbatim` — the speaker's actual words, trimmed. This is the evidence.
- `slots` — the filled values.
- `slot_types` — what KIND each slot is: `exercise`, `muscle`, `number`,
  `metric`, `day`, `condition`, `bodypart`, `equipment`, `phase`.
  This matters as much as the predicate: a lever needs to know what to
  resolve each slot against.
- `scope` — one of `per_set`, `per_exercise`, `per_session`, `per_week`,
  `per_muscle`, `per_block`, `always`, or null.

## Rules

1. **One instruction, one row.** "Start with compounds and finish with
   isolation" is two: a `bookend(start, category)` and a
   `bookend(finish, category)`.
2. **Imperatives only.** "Stretch-mediated hypertrophy is real" is a
   claim and belongs to another wave. "Train the muscle in its stretched
   position" is an instruction and belongs here.
3. **Normalise the predicate, keep the words.** Two speakers saying
   "never do behind-the-neck press" and "I'd avoid upright rows" are both
   `avoid(exercise)`. Same grammar, different slot. Recording them under
   one predicate is what makes the count meaningful.
4. **Conditionals are first-class.** "If your elbows hurt, switch to a
   neutral grip" is `conditional(symptom, substitution)` — a shape the
   current enum cannot express at all. Do not discard it for lack of a
   home.
5. **Do not judge the advice.** A grammar's frequency is what is being
   measured, not whether the instruction is correct. Record shapes from
   speakers you think are wrong.
6. **Skip the un-actionable.** "Train hard", "stay consistent", "trust
   the process" have no slots and cannot become a lever. Motivational
   language is not an instruction.
7. **An empty transcript is a real result.** Say so rather than padding.

## What makes this useful

The deliverable is a frequency table over predicates, weighted by how
many DISTINCT speakers use each. A grammar used 300 times by one person
is that person's verbal tic. Used 40 times across 15 speakers, it is a
shape the language actually has — and a lever worth building.

So in your summary, always report: the predicates you saw, how many
instances of each, and **which ones the four-item list above cannot
express**. That last group is the finding.
