# Corpus miss sweep — the demand-driven research loop

The `corpus_misses` table collects the questions Coach's research
library couldn't answer. Periodically (or when the owner asks):

1. Pull the open queue:
   `./node_modules/.bin/supabase db query --linked "SELECT id, question, created_at FROM corpus_misses WHERE status = 'open' ORDER BY created_at"`
2. Cluster the questions into topics; for each topic worth a pass, run
   the established swarm shape: route (tools/youtube-research/route_*.py
   pattern) → brief → Sonnet deep-read batches → findings f-*.json.
3. Rebuild the consolidated lookup and reseed:
   regenerate via the build snippet in the 20260822000007 migration's
   history (findings.json builder in the session log), then a new
   migration appending the new rows.
4. Mark swept questions:
   `UPDATE corpus_misses SET status = 'researched' WHERE id IN (...)`

The client cache refreshes itself on next launch after a disk hit.
