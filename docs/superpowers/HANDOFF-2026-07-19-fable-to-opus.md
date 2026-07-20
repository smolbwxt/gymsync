# Controller Handoff — Fable → Opus (2026-07-19)

**Read this first, in full, before doing anything.** You (Opus) are taking over as the
controller of GymSync's swarm-based development. This document is the durable transfer of
state, method, and law. The previous controller (Fable) ran eleven shipped phases with the
cadence described here; your job is to continue it, not reinvent it.

## 0. The three sources of truth, in precedence order

1. **`.superpowers/sdd/progress.md`** (gitignored, machine-local) — the execution ledger.
   Every task, review verdict, fix wave, controller decision, production incident, and
   deferral is appended there. After any context loss, trust the ledger + `git log` over
   your own recollection. Search it before re-deriving anything.
2. **This document** — method + law + state snapshot as of tonight.
3. **`docs/superpowers/plans/2026-07-16-remaining-build-roadmap.md`** — the user-committed
   phase order and scope. Phases E→P→U→S→F→M→L→H→O→W are SHIPPED. Remaining: **C → V → D**.

Project memory (`~/.claude/projects/g--Projects-Midas/memory/project_gymsync.md`) carries a
compressed version of all of this and the full credential/CI/gotcha reference — it loads
into your context automatically. The Midas repo's CLAUDE.md does NOT govern GymSync.

## 1. State snapshot (tonight, 2026-07-19)

- **master** = purpose-string fix merge (build 230 = the retry deploy after build 229's
  export-validation failure; it is the FIRST shipped watch build). If the deploy watcher
  died before confirming: `gh run list --branch master --workflow ios.yml --limit 1` —
  if deploy-testflight failed AGAIN, read the export log; risks 1-3 (XcodeGen#1613 embed,
  watch AppIcon, HealthKit provisioning) all cleared empirically on 229's attempt, so any
  new failure is a NEW requirement — diagnose fresh, fix config-only direct via tiny
  branch-merge as precedented in the ledger.
- **feature/watch-turn-advance** (I-2, user-ruled: watch-logged set advances the turn):
  implemented (af674a6), review APPROVED (no fixes), branch CI was in_progress at handoff
  time. **Your first action: check that run; on green, merge --no-ff to master** (message
  idiom in git log), which ships as the next build. On red: read the failure, fix per the
  controller-fix precedent (small compile/test errors are controller-scale; see §4).
- **User's pending items** (they know; don't nag, but track): Sentry DSN → GH secret
  `SENTRY_DSN` + .env.local (activates the DSN-gated integration, zero code needed);
  Google OAuth consent screen (unlocks the GCal sub-phase — schema live since Phase H);
  Twilio Verify + legal review (hard prerequisite for Phase V); campaign content (Phase C);
  the 785-orphan storage `--apply` decision; the Plates-on-inline-card veto (silence=keep);
  **mandatory watch e2e QA on build 230** — the HR leg NEVER ran end-to-end before f61a337
  (dead-path fix); the named check is gate finding I-1 (below).
- **Offered but not yet approved: the debt-zero sprint** (§6). If the user says
  "run the debt sprint," execute it before Phase C.

## 2. The operating cadence (this is what made 11 phases work — keep it)

Per phase: write compact **spec** (`docs/superpowers/specs/`) + **plan**
(`docs/superpowers/plans/`) → commit on a `feature/<phase>` branch → per task:

1. `bash "$SK/scripts/task-brief" PLAN N` (SK = the superpowers SDD skill dir) → dispatch a
   FRESH implementer subagent (usually **sonnet**) with: one-line context, the brief path,
   carried-in requirements from prior reviews, the discipline block (§3), report path
   `.superpowers/sdd/task-N-report.md`, and "COMMIT BUT NEVER PUSH".
2. Controller pushes → CI runs (CI is the ONLY Swift compiler — see §3.1).
3. `bash "$SK/scripts/review-package" BASE HEAD` → dispatch a reviewer (sonnet) with the
   brief+report+diff paths and task-specific attention points. Demand TWO verdicts
   (spec compliance + task quality) and live verification where possible (pgTAP runs,
   db_query probes, SDK-source fetches via `gh api` — reviewers who verify against
   reality catch what report-readers miss; the ledger is full of proof).
4. Critical/Important findings → ONE fix subagent per wave (resume the same agent via
   SendMessage when it has context; dispatch FRESH after an agent dies — resumed dead
   agents on the same context often die again). Re-review (resume the reviewer — it holds
   the trace context). Minors → ledger for the gate.
5. Repeat until clean, ledger `Task N: COMPLETE`, next task. Tasks are SERIAL (parallel
   implementers corrupt review-package ranges) except when files are provably disjoint
   AND all prior work is committed+pushed.
6. Phase gate: `review-package $(git merge-base master HEAD) HEAD` → whole-branch review
   on **the most capable model available to you**, charged with cross-task seams, the
   phase's binding laws end-to-end, ledger-Minor triage, and live probes. On READY:
   merge --no-ff to master (auto-deploys TestFlight; build# = github.run_number), watch
   the deploy, ledger the handoff list.

**Controller-fix precedent**: tightly-scoped, reviewer-prescribed or CI-diagnosed fixes
(one-liners, doc rot, isolation annotations, unwraps) are applied directly by the
controller with a conventional commit — dispatching a fixer for a two-line change wastes
a context. Anything with design judgment gets a subagent.

**Ledger discipline**: append one line per event to `.superpowers/sdd/progress.md` AS YOU
GO (task complete, review verdict, fix wave, CI result, decision + rationale). Compaction
WILL happen; the ledger is the recovery map. Trust it over memory.

## 3. The laws (violations have all actually happened; each law is a scar)

### 3.1 Build/verify
- **Swift compiles ONLY in GitHub Actions CI** (macos-15, XcodeGen from
  `GymSyncApp/project.yml`; Xcode project never committed). Implementers cite real
  declarations file:line for every project API; no guessed signatures. CI failures are
  diagnosed from `gh run view <id> --log-failed` (grep for `error:` / `Failing tests`).
  Compile errors surface ONE PER RUN when early failures mask later ones — expect the
  onion. Backend verifies via `node scripts/run_pgtap.js` (TRUE totals — never summarize
  optimistically) + `node scripts/db_query.js` (read-only probes). Deno tests for Edge
  Functions.
- **@objc-optional near-miss selectors compile and die silently** (RoomDelegate,
  WCSessionDelegate). ANY delegate conformance to an Apple @objc protocol must be
  verified char-for-char against the SDK source (`gh api` the repo, e.g.
  livekit/client-sdk-swift). Same family: WatchConnectivity BIFURCATES delivery by
  reply-handler presence — implement BOTH `didReceiveMessage` variants or traffic
  silently drops (this killed the entire HR leg once).
- **Swift concurrency traps** (each cost a CI round-trip): `let x = true` is OMITTED from
  the memberwise init (must be `var` for an overridable default); a `@MainActor` protocol
  makes conformers' synthesized inits MainActor-isolated — default-argument expressions
  evaluate OUTSIDE the actor, so stateless conformers need explicit `nonisolated init()`;
  test classes touching MainActor-isolated statics need `@MainActor`; plain `private var`
  stored properties on View structs privatize the synthesized init (`@State private`
  exempt).
- **Foundation quirks**: `Decimal(string:)` parses whitespace-only AND lone separators as
  0, not nil (the shared `Decimal.parseUserInput` helper owns all such quirks — route new
  parse sites through it).

### 3.2 Backend
- **Applied migrations are append-only; fix-forward only.** Next timestamp after the
  latest existing. Apply ONLY via
  `npx supabase db push --db-url "postgresql://postgres.chjkkwqwdlmaxacwglzm:$DB_PASS@aws-0-ca-central-1.pooler.supabase.com:5432/postgres" --yes`
  (DB_PASS from `.env.local` SUPABASE_DB_PASSWORD; NEVER echo secrets).
- **Every migration ships pgTAP** (positive AND negative RLS both directions = blocker).
  RLS UPDATE/DELETE denials silently no-op — assert via RETURNING-count CTEs, NOT
  throws_ok. Watch plan(N)-vs-ran mismatches (the runner's heuristic misses them).
- **Security-sensitive DEFINER helpers live in the locked `private` schema** (pattern:
  migration 20260722000001). PostgREST mints /rpc/ endpoints for every public function —
  a relationship helper in public schema is an oracle. THREE residual oracles remain
  (§6). **EXECUTE is checked on every function OID in a compiled RLS expression
  regardless of short-circuit reachability** — dependency inventories come from live
  `pg_policies`, NEVER repo grep (a grep-based inventory caused a production outage of
  all chat sends; ledger has the incident).
- **CREATE OR REPLACE does NOT reset grants; DROP+CREATE and signature changes DO.**
  Supabase platform default grants make naive column-level REVOKE a no-op — use
  table-wide REVOKE ALL + column-scoped GRANT (proven in the T5/H work).
- **The clobber class**: `user_settings` full-row upserts must preserve concurrent
  fields — every writer routes through `ThemeStore.noteExternalSettingsWrite`. New
  user-preference fields extend the merge rule or get their own table.
- **RLS-recursion** (Phase C scar): a subquery or function call inside a policy
  `USING`/`WITH CHECK` evaluates with the INVOKING role's privileges, so any table
  it references has ITS OWN RLS applied for that same role. A gate that must "see
  past" a row's own visibility restriction (e.g. check a draft campaign's
  draft-ness when the caller can't SELECT it) CANNOT use an inline `EXISTS`/`NOT
  EXISTS` — it inherits the very restriction it exists to enforce, and goes
  silently vacuous. The only honest bypass is a `SECURITY DEFINER` function owned
  by an RLS-exempt role (the `private.is_campaign_draft` fix). AUDIT HEURISTIC:
  inline `EXISTS` against an RLS table inside a policy → ask "is that table visible
  to the invoking role in the FAILING case?" If not, the gate does nothing.
- **Realtime publication with the table** (Phase C gate scar): any table consumed
  via `postgres_changes` (a live-updating UI surface) MUST be added to the
  `supabase_realtime` publication (`ALTER PUBLICATION supabase_realtime ADD TABLE
  ...`) in the SAME migration that creates it, AND ship a pgTAP assertion against
  `pg_publication_tables`. pgTAP cannot observe WAL and hermetic tests cannot
  observe delivery, so a missing `ADD TABLE` makes a "live" bar structurally dead
  yet passes every other check — caught only at the whole-branch gate once, via a
  direct `pg_publication_tables` probe. The membership assertion is the regression
  lock. (Precedent the campaigns migration should have followed:
  `20260720000001_session_kudos.sql`'s own "publication in the same migration" law.)

### 3.3 Product/privacy laws
- **HR data is EPHEMERAL**: never persisted, never logged (no bpm in AppLogger/Sentry),
  broadcast-only Realtime (`session:{id}:hr`, 1 msg/5s/user). The opt-out guarantee is
  anchored at the PHONE RELAY's live read of `ThemeStore.shared.shareHeartRate` — do not
  weaken that anchor. Purpose strings: Apple's export validation demands them per
  ENTITLEMENT, not per API use (build 229's failure).
- **Permission discipline**: NO permission prompt at launch or outside an explicit user
  action, ever (HealthKit, EventKit, notifications, HR).
- **AUDIO SACRED RULE**: AudioSessionManager.configure ordering before LiveKit connect
  never changes. Voice concurrency rides lifecycleEpoch + per-connection Room
  generations + identity-gated delegates (the identity gate is LOAD-BEARING — the SDK
  fires didDisconnectWithError on intentional teardowns too).
- **WatchEnvelope payloads evolve ADDITIVELY**: decodeIfPresent + default for every new
  field, old-shape decode test extended every time; shell `v` stays 1 for additive
  changes. HR rides sendMessage (transient), NEVER updateApplicationContext (OS persists
  it to disk — biometric data must not touch it).
- **Watch state derivation**: derive-from-observed-state beats push-at-action-sites
  (the isActive story: action-site pushes only reach the acting device; every
  participant's phone derives from its own realtime echo). `WatchDisplayFormatting.
  isSessionActive` is ended-detection and fail-open by design.

### 3.4 Git/process
- **NEVER `git add -A`** (`.superpowers/`, `.env.local`, `Inspo/` are scratch/secrets).
  Stage explicit paths. Implementers commit but never push; the controller pushes.
- **Never commit to master directly except merges** (tiny config fixes ride a
  fix/<name> branch merged immediately — precedent in ledger).
- Secrets live in `.env.local` + GH Actions secrets only. The .p8 keys live in
  `G:\Projects\Keys\GymSync\`. Never echo secret values anywhere.
- Reports go to `.superpowers/sdd/task-N-report.md` (gitignored by design — never
  force-add). Cite dispatch-level instructions as dispatch-level, not as "the brief".

## 4. Model selection (adapt to your reality)

Fable ran: implementers/reviewers/fixers on **sonnet**, whole-branch gates on **fable**.
As Opus, run gates YOURSELF-equivalent (dispatch on opus) and keep sonnet for the
per-task loop — the leverage is in the review layer's verification demands, not the
model tier. Turn count beats token price; a well-briefed sonnet with a demanding
reviewer matched bigger models all arc. When a background agent dies mid-flight
(API error, overload), dispatch FRESH with the context re-composed — do not resume the
corpse. When the same agent holds valuable context (an SDK ruling, a trace), RESUME it
via SendMessage for the re-review instead of cold-starting.

## 5. Remaining roadmap (the docket)

1. **Finish in-flight** (§1): I-2 merge; build-230 confirmation.
2. **Debt-zero sprint** (if user approves; §6) — one branch, one gate, before C.
3. **Phase C — Seasonal campaigns**: spec Flow 8 (campaigns/participants/progress tables
   + trigger, Library sub-tab + Home carousel, live community progress via
   postgres_changes, per-campaign leaderboard, badge + system message). Seed a test
   campaign; real content is the user's. Write spec+plan per the cadence; ~4-5 tasks.
4. **Phase V — Venue hubs** (18+, GATED on user's Twilio Verify + legal/privacy-policy
   work): spec Flow 9 + §6.7. Safety measures are mandatory scope. Do NOT start until
   the prerequisites exist.
5. **Phase D — Design Sharpening** (finale): family-batched designer briefs w/ real
   harness captures (`docs/design/requests/` + upload to the claude.ai/design project),
   parity-closed-loop per family (designer frames → DesignSync pull → render_proofs.js →
   frame-map entries → fix-wave → deviations pruned). Families: Social, Discover/Library,
   Moderation/Settings, Stats, Watch, Campaigns/Venues. Art track (app icon, pack
   artwork, exercise imagery) parallelizes ANY time. Phase D's accumulated queue:
   §6.5 sharing-paused surface, group-flow HR consent toggle, zone colors/boundaries
   sign-off, mixer coming-soon toggles → real, ~28 deviations entries, the designer-note
   backlog. Definition of done: every app-*.png maps to an authoritative frame in-band;
   deviations near-empty; real icon + artwork.
6. **Release gates** per roadmap tail: pre-GA items are largely done (Phase O T7);
   verify the roadmap's release section before GA.

## 6. The debt-zero sprint (pre-approved shape, awaiting user's go)

One branch (`feature/debt-zero`), one day of agent time, one gate:
1. Relocate the 3 residual public DEFINER oracles (`routine_has_active_session_for_user`
   FIRST — its routine_id input became publicly discoverable via Discover;
   `is_series_organizer`, `proposal_session_id`) — same private-schema pattern +
   live-pg_policies inventory + pgTAP re-proofs.
2. Commit `Package.resolved` (or pin supabase-swift exactly) — archive-time SDK behavior
   currently floats; load-bearing for the I-1 channel-collision class.
3. Defensive fix for I-1 regardless of QA outcome: `HeartRateBroadcastService.publish`
   must not create/remove a disposable channel on a topic the same client already holds
   (publish through the held channel; never removeChannel one you didn't create). Same
   audit for the T2 soundboard disposable-channel path.
4. Replay-failure toast surface (offline queue's lastPermanentFailure has no UI).
5. `forceSignedOutAfterDeletion` purges the deleted user's queued sets.
6. Dead code: `SessionCalendarSyncStore.load(defaults:)`; `routineLabel(for:)`
   placeholder; the pre-existing `GroupSessionLiveView` setIndex mis-citation (line
   1766 not 2158); doc-rot sweep.
7. Gate + merge.

## 7. Known open questions / QA-dependent items

- **I-1 (channel collision)**: on the SHARING phone, do pills keep updating past ~15s of
  relaying? If they freeze → the disposable-channel teardown is real → fix per §6.3.
  Sibling check: after a watch soundboard tap, does the phone still receive others'
  sounds?
- Watch e2e QA list lives in `.superpowers/sdd/task-5-report.md` (Phase W) + the gate's
  checklist in the ledger. HealthKit prompt timing, zero-Health-entries, session-ended
  immediacy, crown-vs-swipe contention.
- Zone boundaries (60/75/90% of fixed 190 max — no profile age field exists) await
  design sign-off (Phase D).
- Recorded product assumptions the user may still veto: Plates on the group inline card;
  group-stats scalars=all-time/leaderboard=current-roster; Edit-Profile pick-persists.

## 8. How to start your first session

1. Read this file, then `git log --oneline -30`, then the ledger tail
   (`tail -100 .superpowers/sdd/progress.md`).
2. Resolve §1's two in-flight threads (I-2 merge; build-230 status).
3. Ask the user ONE question: "debt sprint first, or straight to Phase C?" Then run the
   cadence. Everything else is in the ledger.

Good luck. The system works — trust the review layer, verify against reality, keep the
ledger honest, and ship.
