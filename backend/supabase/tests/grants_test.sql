-- The exact table privileges of the app's role, and nothing for anon.
-- Default privileges once granted TRUNCATE (which ignores RLS) on every
-- table; this pins the list so it cannot come back unnoticed.
begin;
select plan(2);
select is(
    (select string_agg(line, ' | ' order by line)
     from (select (g.table_name::text || ':' || string_agg(g.privilege_type::text, ',' order by g.privilege_type::text)) collate "C" as line
           from information_schema.role_table_grants g
           where g.grantee = 'authenticated' and g.table_schema = 'public'
             -- The community objects (lot C) are pinned, the same way, in
             -- community_outings_test.sql.
             and g.table_name not in ('community_zones', 'community_profiles', 'community_dogs',
                                      'community_organizers', 'community_moderators', 'outings',
                                      'outing_participants', 'outing_dogs', 'outing_updates', 'reports',
                                      'blocks', 'visible_outings', 'my_outings', 'my_blocks')
           group by g.table_name::text) t),
    ('daily_tips:SELECT | dogs:INSERT,SELECT,UPDATE | household_invites:INSERT,SELECT,UPDATE'
     || ' | household_members:DELETE,SELECT,UPDATE | households:DELETE,INSERT,SELECT,UPDATE'
     || ' | member_profiles:INSERT,SELECT,UPDATE | planned_walks:INSERT,SELECT,UPDATE'
     || ' | walk_dogs:DELETE,INSERT,SELECT | walks:INSERT,SELECT,UPDATE') collate "C",
    'authenticated holds exactly the privileges the policies expect');
-- One exception, on purpose: the daily tips, editorial and the same for
-- everyone, read without an account (20261007220000_household_details).
select is((select string_agg(table_name::text || ':' || privilege_type::text, ' | ' order by table_name::text)
           from information_schema.role_table_grants
           where grantee = 'anon' and table_schema = 'public'),
          'daily_tips:SELECT', 'anon reads the daily tips and nothing else');
select * from finish();
rollback;
