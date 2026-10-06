-- Live household journal (ADR 0008): a change to a walk rings the other
-- members' iPhones, which then pull through the usual sync.
--
-- Only `walks` is published. Realtime applies row level security to the
-- rows it sends (supabase.com/docs/guides/realtime/postgres-changes), except
-- for DELETE, which it cannot check. Walks are never deleted, only
-- tombstoned with an UPDATE, so every event goes through the read policy.
alter publication supabase_realtime add table public.walks;
