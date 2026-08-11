-- Sound reactions (owner decision 2026-08-11): react to chat messages and
-- pump-check posts with soundboard sounds. Stored in the EXISTING reaction
-- tables as emoji = 'snd:{slug}' rows — same toggle semantics, same
-- realtime, zero new tables. Only owners (sound in their soundboard
-- favorites rack) can ATTACH a sound; anyone who can see the reaction can
-- tap it to play (playback is client-side from the world-readable catalog).

-- Ownership predicate: the user's favorites rack holds the slug.
CREATE OR REPLACE FUNCTION private.owns_soundboard_sound(p_user_id uuid, p_slug text)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.soundboard_favorites f
    WHERE f.user_id = p_user_id
      AND p_slug = ANY (f.slugs)
  );
$$;

-- RESTRICTIVE policies AND onto the existing permissive INSERT policies:
-- emoji rows pass untouched; 'snd:' rows additionally require ownership.
-- (Restrictive-by-name so the existing policies stay exactly as shipped.)
CREATE POLICY "sound reactions require ownership"
  ON public.chat_message_reactions
  AS RESTRICTIVE
  FOR INSERT
  TO authenticated
  WITH CHECK (
    emoji NOT LIKE 'snd:%'
    OR private.owns_soundboard_sound(auth.uid(), substring(emoji FROM 5))
  );

-- post_reactions ships a fixed emoji CHECK — widen it to admit sound rows.
ALTER TABLE public.post_reactions
  DROP CONSTRAINT IF EXISTS post_reactions_emoji_check;
ALTER TABLE public.post_reactions
  ADD CONSTRAINT post_reactions_emoji_check
  CHECK (
    emoji IN ('💪', '🔥', '👏', '🏆', '⚡')
    OR (emoji LIKE 'snd:%' AND char_length(emoji) BETWEEN 5 AND 68)
  );

CREATE POLICY "sound reactions require ownership"
  ON public.post_reactions
  AS RESTRICTIVE
  FOR INSERT
  TO authenticated
  WITH CHECK (
    emoji NOT LIKE 'snd:%'
    OR private.owns_soundboard_sound(auth.uid(), substring(emoji FROM 5))
  );
