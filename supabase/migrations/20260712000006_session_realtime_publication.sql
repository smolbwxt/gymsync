-- Phase 3a hotfix: LobbyRealtimeService subscribes to these via postgres_changes,
-- but they were never published — lobby views received no live events.
-- RLS (WALRUS) scopes events to session participants.
ALTER PUBLICATION supabase_realtime ADD TABLE public.sessions;
ALTER PUBLICATION supabase_realtime ADD TABLE public.session_participants;
ALTER PUBLICATION supabase_realtime ADD TABLE public.routine_proposals;
ALTER PUBLICATION supabase_realtime ADD TABLE public.routine_proposal_votes;
