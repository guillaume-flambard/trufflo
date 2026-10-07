-- Walks and planned walks are published to Realtime, and neither is ever hard
-- deleted (Realtime cannot apply row level security to a DELETE).
begin;
select plan(4);
select ok(exists (select 1 from pg_publication_tables
                  where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'walks'),
          'walks are published to Realtime');
select is((select count(*)::int from pg_publication_tables
           where pubname = 'supabase_realtime' and schemaname = 'public'
             and tablename not in ('walks', 'planned_walks')),
          0, 'no other table of the household is published');
select ok(not has_table_privilege('authenticated', 'public.walks', 'DELETE'),
          'nobody can hard delete a walk, so every event goes through row level security');
select ok(not has_table_privilege('authenticated', 'public.planned_walks', 'DELETE'),
          'nobody can hard delete a planned walk either');
select * from finish();
rollback;
