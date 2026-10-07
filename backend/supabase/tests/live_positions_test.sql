-- Live positions of the foyer (2026-10-08): members only, rounded by the
-- server, expired after two minutes, each member writes only their own.
begin;
select plan(10);

insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-00000000000a', 'anne@example.test'),
    ('00000000-0000-0000-0000-00000000000b', 'bruno@example.test'),
    ('00000000-0000-0000-0000-00000000000d', 'driss@example.test');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000a","role":"authenticated"}', true);
set local role authenticated;
insert into public.households (id, name) values ('11111111-1111-1111-1111-111111111111', 'Maison');
insert into public.household_invites (household_id, role, token) values
    ('11111111-1111-1111-1111-111111111111', 'reader', 'token-bruno');
select lives_ok(
    $$ insert into public.live_positions (household_id, latitude, longitude)
       values ('11111111-1111-1111-1111-111111111111', 48.8812345678, 2.3812345678) $$,
    'a member shares their position');
select is((select latitude || ',' || longitude from public.live_positions), '48.8812,2.3812',
          'the server rounds to about ten metres, whatever the phone sends');

reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000b","role":"authenticated"}', true);
set local role authenticated;
select public.accept_household_invite('token-bruno');
select is((select count(*)::int from public.live_positions), 1, 'another member of the household reads it');
select throws_ok(
    $$ insert into public.live_positions (household_id, user_id, latitude, longitude)
       values ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-00000000000a', 0, 0)
       on conflict (household_id, user_id) do update set latitude = excluded.latitude $$,
    '42501', null, 'nobody writes someone else''s position');
delete from public.live_positions where user_id = '00000000-0000-0000-0000-00000000000a';
reset role;
select is((select count(*)::int from public.live_positions), 1, 'nobody deletes someone else''s position');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000d","role":"authenticated"}', true);
set local role authenticated;
select is((select count(*)::int from public.live_positions), 0, 'an outsider reads nothing');
select throws_ok(
    $$ insert into public.live_positions (household_id, latitude, longitude)
       values ('11111111-1111-1111-1111-111111111111', 48.88, 2.38) $$,
    '42501', null, 'an outsider cannot share into a household');

-- An expired position is invisible.
reset role;
alter table public.live_positions disable trigger live_positions_rules;
update public.live_positions set expires_at = now() - interval '1 second';
alter table public.live_positions enable trigger live_positions_rules;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000b","role":"authenticated"}', true);
set local role authenticated;
select is((select count(*)::int from public.live_positions), 0, 'an expired position is no longer read');

-- Stopping: the member deletes their own row.
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000a","role":"authenticated"}', true);
set local role authenticated;
delete from public.live_positions where user_id = '00000000-0000-0000-0000-00000000000a';
reset role;
select is((select count(*)::int from public.live_positions), 0, 'a member stops sharing by deleting their row');
select ok(not exists (select 1 from pg_publication_tables where tablename = 'live_positions'),
          'live positions are not published to Realtime');

select * from finish();
rollback;
