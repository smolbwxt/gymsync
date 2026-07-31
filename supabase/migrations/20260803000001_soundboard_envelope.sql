-- Composite v5 plate tokens: every sound carries its clipped waveform
-- envelope (22 RMS buckets, 1..8) and its pre-clip length. Playback assets
-- in the `soundboard` bucket are clipped to the 5-second cap at import
-- time (scripts/import_soundboard_pilot.js); original_duration_ms records
-- what the scissors took so the Rack Room can draw the dimmed tail.
alter table public.soundboard_sounds
  add column if not exists envelope smallint[],
  add column if not exists original_duration_ms integer;
