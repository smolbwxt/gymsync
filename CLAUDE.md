# Claude Code Project Notes — GymSync

Sessions for this project normally run from the Midas cwd (`G:/Projects/Midas`) so the persistent memory stays attached; the Midas `CLAUDE.md` carries the same policy. Process: subagent-driven development with a controller session — specs in `docs/superpowers/specs/`, plans in `docs/superpowers/plans/`, per-plan ledgers under `.superpowers/sdd/` (gitignored). Swift compiles only in GitHub Actions; the owner requires a real CI render (proof card) before any design change merges; the owner has granted automerge (merge on green after review + cards sent).

## Agent dispatch policy (2026-09-12) — token economy

GymSync sessions run from the Midas cwd so memory stays attached; this policy lives here for that reason and is
mirrored in `G:/Projects/GymSync/CLAUDE.md`. **Why:** four account-wide session-limit outages on 2026-09-11/12.
The spend was dominated by Opus implementers idling through 10-minute `gh run watch` calls (every re-issue
re-reads a 300k-token context) and by agents reading whole screenshot artifacts frame by frame.

**Roles**
- **Controller (this session):** migration gates, ledgers, briefs (as files), PR bodies, proof cards, merges, and
  ALL CI waiting through `Monitor` (zero model tokens while waiting). The controller looks at one composed card,
  never at raw frames one by one.
- **Implementers never wait on CI.** Commit → push → return SHAs and a one-line summary. Red run → the controller
  resumes the SAME implementer with the failing log excerpt (its context is cached). Green run → the controller
  composes the card; frame descriptions, when needed, go to Haiku.

**Model ladder (subagents only — never Fable, never `fork`)**
- **Haiku 4.5:** mechanical — frame descriptions, persisting returned text, grep-verification lists, comment-only
  edits, exact-spec seed or data tweaks, checklist checks.
- **Sonnet 5:** scoped re-reviews; task reviews of diffs ≤ 3 files; tests-only batches; single-file fixes with
  exact instructions; pgTAP/SQL from exact specs; context maps via the `Explore` agent type (read-only,
  excerpt-reading, cheap).
- **Opus 5:** multi-file feature streams, plans, spec-compliance reviews of L tasks, final whole-branch reviews,
  cross-file debugging, anything needing design judgment.
- **Specialist lenses** instead of a second general review: `pr-review-toolkit:comment-analyzer` (stale comments,
  the most frequent finding class today), `pr-review-toolkit:silent-failure-hunter` (swallowed errors),
  `pr-review-toolkit:pr-test-analyzer` (tests that assert nothing) — always with an explicit `model: sonnet`;
  an agent definition without a pinned model inherits the parent.

**Limits and habits**
- At most **two Opus agents at once**; one Sonnet or Haiku alongside is fine. Dispatch the long pole first.
- **Resume over re-dispatch:** fix rounds and follow-ups resume the agent (cached context); a fresh agent only after
  round 3 or a model escalation.
- Dispatch prompts stay under ~40 lines; requirements live in a brief file; never paste history. Agents return
  text (the harness blocks `report*.md` writes); the controller persists it.
- Artifacts: download into a fresh directory, read only the frames a task names, diff against master's latest run
  with the status bar masked.
- After a rate-limit reset, check `git log` and `gh run list` per worktree before resuming anything — most of the
  time the work landed before the kill.
