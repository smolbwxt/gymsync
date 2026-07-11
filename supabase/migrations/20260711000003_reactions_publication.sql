-- INSERT events only are consumed by clients. DELETE events are NOT added to
-- client logic: Supabase realtime does not RLS-filter DELETE payloads, so
-- un-reactions refresh on next fetch instead of streaming.
ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_message_reactions;
