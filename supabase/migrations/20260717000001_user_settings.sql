-- ============================================================
-- Canvas Completion Task 2: You tab Settings Hub — user_settings
-- Single row per user: default rest timer duration + active palette.
-- Absence of a row means the DEFAULT column values apply (same
-- absence-means-default convention as notification_prefs,
-- 20260716000001_push_schema.sql) — the repository's `get()` returns those
-- defaults client-side when no row exists yet, so no bootstrap insert is
-- required on signup.
-- ============================================================

CREATE TABLE public.user_settings (
  user_id             uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  default_rest_seconds int NOT NULL DEFAULT 120
                        CHECK (default_rest_seconds BETWEEN 15 AND 900),
  palette             text NOT NULL DEFAULT 'midnight'
                        CHECK (palette IN ('midnight', 'arena', 'ink', 'modernist')),
  updated_at          timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.user_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "owner manages own settings"
  ON public.user_settings FOR ALL TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());
