-- 20260913000104_soundboard_drop.sql
--
-- APPLIED LIVE 2026-09-18 18:46:12 UTC (schema_migrations version
-- 20260918184612).
--
-- IRREVERSIBLE. Spec: docs/superpowers/specs/2026-09-12-group-session-and-
-- lobby-design.md (owner decisions 8 and 14 -- the throwables are tabled
-- indefinitely). Plan: docs/superpowers/plans/2026-09-13-group-session-
-- phase-b-plan.md, task D5, "the five data decisions," decision 5 --
-- "sound reactions are rows, not a table."
--
-- ── The irreversible gate (plan constraint 9): tag, then removal, then
--    this drop. All three confirmed before this file was written:
--
--   1. The archive tag is on the remote.
--      archive/soundboard-throwables-2026-09 -> 8a5a13043de694584463c9f9
--      87b2ee0c3f811a0f (annotated; tag object 99cdf5b8f059dbb7e3a46d5f
--      7d5b473e018113d3), listing the seven soundboard implementation
--      files at that commit. A tag archives code; it does not archive
--      data -- which is why (2) exists.
--   2. The live rows are exported, by hand, to a file in the workspace:
--      .superpowers/sdd/2026-09-13-group-session-phase-b-plan/soundboard-
--      rows-2026-09-13.json (exported_at 2026-09-13T19:57:46Z) --
--      49 soundboard_sounds rows, 2 soundboard_favorites rows, 0 'snd:%'
--      rows in chat_message_reactions, 0 in post_reactions.
--      Re-counted read-only against chjkkwqwdlmaxacwglzm immediately
--      before writing this migration, 2026-09-18 05:16 UTC: 49 / 2 / 0 /
--      0 -- unchanged since the export, so the export is a complete
--      record of everything this file destroys.
--   3. The app no longer reads any of it: S11 (the soundboard leaves the
--      app) and S12 (the reaction vocabulary becomes emoji only) are
--      pushed on feat/group-session-phase-b-app, tip 9165e71.
--
-- ── Why the drop has four parts. 20260811000004_sound_reactions.sql
--    added NO table. It added private.owns_soundboard_sound, two
--    RESTRICTIVE INSERT policies (one per reaction table), and it WIDENED
--    post_reactions_emoji_check to admit emoji LIKE 'snd:%'. So undoing
--    it means undoing four separate things, in an order that matters:
--    the two policies call the ownership function, so they must go before
--    it, and the function reads soundboard_favorites, so it must go
--    before the tables.
--
-- ── The part that is not an undo. chat_message_reactions has never had
--    an emoji CHECK at all (20260710000003_create_chat.sql:20-25): its
--    column accepts any text, and the restrictive policy added in
--    20260811000004 was the only thing keeping unowned 'snd:' rows out.
--    Dropping that policy with nothing in its place would leave the
--    column MORE permissive than it was before the soundboard ever
--    shipped. Part 3 therefore ADDS a CHECK there -- and deliberately
--    only the narrowest one that closes the 'snd:' door
--    (emoji NOT LIKE 'snd:%'), not post_reactions' fixed five-emoji list:
--    that table keeps its open vocabulary, which is what it has always
--    had.
--
-- ── What this migration deliberately leaves alone:
--    * storage. The 'soundboard' bucket, its "authenticated users read
--      soundboard files" policy and the objects under it stay; the
--      objects are removed by hand after this is green
--      (scripts/cleanup_storage_orphans.js), per decision 5.
--    * chat_messages.kind = 'soundboard_echo' and the historical rows
--      holding it. Narrowing that CHECK would invalidate shipped chat
--      history, which is a separate decision nobody has made.
--
-- ── One object decision 5 did not name, added by ruling R-B19:
--    private.touch_soundboard_favorites_updated_at() (20260726000005)
--    goes too, at the end of part 4. Decision 5 was written from
--    20260811000004's contents and did not enumerate this function --
--    it belongs to the favorites table's own touch trigger, not to the
--    sound-reaction feature. DROP TABLE takes the trigger with it but
--    would leave the function standing: no table, no trigger, no caller,
--    and a body that names a relation that no longer exists. It is
--    dropped in the same irreversible migration rather than left as a
--    dangling object for a later sweep to puzzle over. The lesson that
--    function encodes -- clock_timestamp(), not now(), or the before/
--    after comparison is equal rather than greater -- survives in its
--    two siblings, private.touch_user_settings_updated_at
--    (20260726000006) and the weekly-goals trigger (20260906000001),
--    both still live and both still proved by their own pgTAP suites.
--
-- Accepted consequence, stated in the plan: a tester still running an
-- older TestFlight build loses the soundboard the moment this is applied.
-- That is what "tabled indefinitely" means, and the tag above is how it
-- comes back if the owner ever reverses.

-- ── 1. The rows ──────────────────────────────────────────────────────────
-- Sound reactions live in the two existing reaction tables as
-- emoji = 'snd:{slug}' rows (20260811000004's header: "same toggle
-- semantics, same realtime, zero new tables"). Both counts were 0 at the
-- export and 0 at the re-count above, so both DELETEs are expected to
-- report 0 -- they are here because a row written between the re-count
-- and the apply would otherwise violate part 3's CHECKs and abort this
-- migration halfway through.
DELETE FROM public.chat_message_reactions WHERE emoji LIKE 'snd:%';
DELETE FROM public.post_reactions         WHERE emoji LIKE 'snd:%';

-- ── 2. The ownership policies ────────────────────────────────────────────
-- Both added by 20260811000004 as RESTRICTIVE INSERT policies that AND
-- onto the shipped permissive ones ("emoji rows pass untouched; 'snd:'
-- rows additionally require ownership"). They call
-- private.owns_soundboard_sound, so they leave before it does.
DROP POLICY IF EXISTS "sound reactions require ownership" ON public.chat_message_reactions;
DROP POLICY IF EXISTS "sound reactions require ownership" ON public.post_reactions;

-- ── 3. The two CHECKs ────────────────────────────────────────────────────
-- post_reactions: restore the emoji-only list it carried from
-- 20260731000001_workout_posts.sql:84 until 20260811000004 widened it.
-- Byte-for-byte the original five kudos emoji, no 'snd:' arm.
ALTER TABLE public.post_reactions DROP CONSTRAINT IF EXISTS post_reactions_emoji_check;
ALTER TABLE public.post_reactions ADD  CONSTRAINT post_reactions_emoji_check
  CHECK (emoji IN ('💪', '🔥', '👏', '🏆', '⚡'));

-- chat_message_reactions never had a CHECK; the restrictive policy was the
-- only gate. Dropping it without this would leave the column MORE
-- permissive than before the soundboard shipped. This closes exactly the
-- 'snd:' door and nothing else -- the smallest change that leaves the
-- table no looser than it was.
ALTER TABLE public.chat_message_reactions ADD CONSTRAINT chat_message_reactions_emoji_check
  CHECK (emoji NOT LIKE 'snd:%');

-- ── 4. The function, then the tables ─────────────────────────────────────
-- owns_soundboard_sound (20260811000004) reads soundboard_favorites;
-- soundboard_favorites (20260717000003_curation.sql:19) and
-- soundboard_sounds (20260715000001_comms_schema.sql:6) have no dependents
-- left once it is gone -- verified read-only before writing: no foreign
-- key references either table, no view or materialized view reads them,
-- no other function's body names them, and neither is in a publication.
DROP FUNCTION IF EXISTS private.owns_soundboard_sound(uuid, text);
DROP TABLE IF EXISTS public.soundboard_favorites;
DROP TABLE IF EXISTS public.soundboard_sounds;

-- The favorites table's own touch trigger function (20260726000005),
-- orphaned by the DROP TABLE above -- the trigger goes with the table, the
-- function does not. Dropped last, after its only trigger has already
-- ceased to exist, so this statement can never be the thing that fails.
DROP FUNCTION IF EXISTS private.touch_soundboard_favorites_updated_at();
