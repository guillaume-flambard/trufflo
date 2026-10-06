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
           group by g.table_name::text) t),
    ('dogs:INSERT,SELECT,UPDATE | household_invites:INSERT,SELECT,UPDATE'
     || ' | household_members:DELETE,SELECT,UPDATE | households:DELETE,INSERT,SELECT,UPDATE'
     || ' | member_profiles:INSERT,SELECT,UPDATE | walk_dogs:DELETE,INSERT,SELECT'
     || ' | walks:INSERT,SELECT,UPDATE') collate "C",
    'authenticated holds exactly the privileges the policies expect');
select is((select count(*)::int from information_schema.role_table_grants
           where grantee = 'anon' and table_schema = 'public'), 0, 'anon holds nothing');
select * from finish();
rollback;
