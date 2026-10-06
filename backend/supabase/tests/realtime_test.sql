-- Only walks are published to Realtime, and they are never hard deleted
-- (Realtime cannot apply row level security to a DELETE).
begin;
select plan(3);
select ok(exists (select 1 from pg_publication_tables
                  where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'walks'),
          'walks are published to Realtime');
select is((select count(*)::int from pg_publication_tables
           where pubname = 'supabase_realtime' and schemaname = 'public' and tablename <> 'walks'),
          0, 'no other table of the household is published');
select ok(not has_table_privilege('authenticated', 'public.walks', 'DELETE'),
          'nobody can hard delete a walk, so every event goes through row level security');
select * from finish();
rollback;
