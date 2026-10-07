-- C-AC-05, the last place, with two real sessions (ADR 0010 « Tests prévus »).
--
-- One place left, two requests, the organizer accepts both at the same time
-- from two connections. Session A accepts and holds its transaction open;
-- session B accepts the other request and must wait on the outing's row lock
-- (SELECT ... FOR UPDATE in private.decide_request). When A commits, B counts
-- again and is refused with 'outing full'. Exactly one acceptance passes.
--
-- The two sessions are dblink connections back into this local database, so
-- the data they race on has to be committed: a third connection writes it
-- and removes it at the end (deleting the users cascades to everything).
-- The password is the local stack's default, never a production one.
begin;
create extension if not exists dblink with schema extensions;
select plan(5);

-- dblink refuses a connection that does not use the password, and the local
-- stack trusts loopback: connect back through the address this session came
-- in on, the Docker network one when `supabase test db` runs the file.
select set_config('race.conn', format('host=%s port=%s dbname=%s user=postgres password=postgres',
                                      host(inet_server_addr()), inet_server_port(), current_database()), true);

select extensions.dblink_connect('setup', current_setting('race.conn'));
select extensions.dblink_connect('a', current_setting('race.conn'));
select extensions.dblink_connect('b', current_setting('race.conn'));

-- Leftovers of an interrupted run first, then the committed world.
select extensions.dblink_exec('setup', $$
    delete from auth.users where id in ('00000000-0000-0000-0000-0000000000a1',
        '00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000000a3') $$);
select extensions.dblink_exec('setup', $$
    begin;
    insert into auth.users (id, email) values
        ('00000000-0000-0000-0000-0000000000a1', 'race-organizer@example.test'),
        ('00000000-0000-0000-0000-0000000000a2', 'race-first@example.test'),
        ('00000000-0000-0000-0000-0000000000a3', 'race-second@example.test');
    insert into public.community_profiles (user_id, display_name, zone_id, adult_declared_at) values
        ('00000000-0000-0000-0000-0000000000a1', 'Organisatrice', 'paris', now()),
        ('00000000-0000-0000-0000-0000000000a2', 'Première', 'paris', now()),
        ('00000000-0000-0000-0000-0000000000a3', 'Seconde', 'paris', now());
    insert into public.community_organizers (user_id, zone_id) values ('00000000-0000-0000-0000-0000000000a1', 'paris');
    insert into public.outings (id, organizer_id, zone_id, starts_at, duration_minutes, meeting_point,
                                human_capacity, dog_capacity)
    values ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000a1', 'paris',
            now() + interval '1 day', 60, 'Une seule place', 1, 5);
    insert into public.outing_participants (outing_id, user_id, status) values
        ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000a2', 'requested'),
        ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000a3', 'requested');
    commit $$);

-- Both sessions act as the organizer, under her role and RLS.
select extensions.dblink_exec('a', $$ begin $$);
select extensions.dblink_exec('a', $$ set local request.jwt.claims to
    '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}' $$);
select extensions.dblink_exec('a', $$ set local role authenticated $$);
select extensions.dblink_exec('b', $$ begin $$);
select extensions.dblink_exec('b', $$ set local request.jwt.claims to
    '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}' $$);
select extensions.dblink_exec('b', $$ set local role authenticated $$);

select set_config('race.b_pid', (select r from extensions.dblink('b', 'select pg_backend_pid()::text') as t(r text)), true);

-- A takes the last place and keeps its transaction open.
select lives_ok(
    $$ select * from extensions.dblink('a', 'select public.decide_request(''00000000-0000-0000-0000-0000000000b1'', ''00000000-0000-0000-0000-0000000000a2'', true)::text') as t(r text) $$,
    'the first acceptance passes');

-- B asks for the same last place, without waiting for the answer.
select extensions.dblink_send_query('b',
    $$ select public.decide_request('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000a3', true) $$);
-- Wait (5 s at most) until B's backend is seen blocked on a lock, not merely slow.
do $$
begin
    for i in 1..50 loop
        exit when exists (select 1 from pg_stat_activity
                          where pid = current_setting('race.b_pid')::int and wait_event_type = 'Lock');
        perform pg_sleep(0.1);
    end loop;
end $$;
select is((select wait_event_type from pg_stat_activity where pid = current_setting('race.b_pid')::int), 'Lock',
          'the second acceptance waits for the outing''s row lock');

-- A commits; B wakes up, counts again, and is refused.
select extensions.dblink_exec('a', $$ commit $$);
select is((select count(*)::int from extensions.dblink_get_result('b', false) as t(r text)), 0,
          'the second acceptance returns no result');
select matches(extensions.dblink_error_message('b'), 'outing full', 'it is refused with outing full');
select * from extensions.dblink_get_result('b', false) as t(r text);
select extensions.dblink_exec('b', $$ rollback $$);

select is((select r from extensions.dblink('setup', $$
              select string_agg(user_id::text || ':' || status, ',' order by user_id)
              from public.outing_participants where outing_id = '00000000-0000-0000-0000-0000000000b1' $$) as t(r text)),
          '00000000-0000-0000-0000-0000000000a2:accepted,00000000-0000-0000-0000-0000000000a3:requested',
          'exactly one person holds the last place');

select extensions.dblink_exec('setup', $$
    delete from auth.users where id in ('00000000-0000-0000-0000-0000000000a1',
        '00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000000a3') $$);
select extensions.dblink_disconnect('a');
select extensions.dblink_disconnect('b');
select extensions.dblink_disconnect('setup');

select * from finish();
rollback;
