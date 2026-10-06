-- Household sharing (PRD F08), played by four people:
--   Anne (owner), Bruno (contributor), Chloé (reader), Driss (outsider).
-- Every check runs as that person, under RLS, through the same grants the app
-- uses. Nothing here uses the service role.
begin;
select plan(25);

-- Users -----------------------------------------------------------------------
insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-00000000000a', 'anne@example.test'),
    ('00000000-0000-0000-0000-00000000000b', 'bruno@example.test'),
    ('00000000-0000-0000-0000-00000000000c', 'chloe@example.test'),
    ('00000000-0000-0000-0000-00000000000d', 'driss@example.test');

-- Privacy: what must never reach the server ----------------------------------
select hasnt_column('public', 'walks', 'note', 'no private note on the server');
select hasnt_column('public', 'walks', 'latitude', 'no coordinate on the server');
select hasnt_table('public', 'track_points', 'no track table on the server');
select hasnt_column('public', 'dogs', 'photo_data', 'no dog photo on the server');

-- Anne creates the household and is its owner ---------------------------------
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000a","role":"authenticated"}', true);
set local role authenticated;
insert into public.households (id, name) values ('11111111-1111-1111-1111-111111111111', 'Maison');
select is(
    (select role from public.household_members where user_id = '00000000-0000-0000-0000-00000000000a'),
    'owner', 'the creator becomes owner');
insert into public.household_invites (household_id, role, token) values
    ('11111111-1111-1111-1111-111111111111', 'contributor', 'token-bruno'),
    ('11111111-1111-1111-1111-111111111111', 'reader', 'token-chloe');
insert into public.household_invites (household_id, role, token, expires_at) values
    ('11111111-1111-1111-1111-111111111111', 'reader', 'token-expired', now() - interval '1 day');
insert into public.dogs (id, household_id, name, breed_kind) values
    ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111', 'Oslo', 'mixed');
insert into public.walks (id, household_id, source, quality, started_at, ended_at, confirmed_seconds) values
    ('33333333-3333-3333-3333-33333333333a', '11111111-1111-1111-1111-111111111111', 'manual', 'manual',
     now() - interval '2 hours', now() - interval '90 minutes', 1800);

-- Driss, an outsider, sees nothing --------------------------------------------
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000d","role":"authenticated"}', true);
set local role authenticated;
select is((select count(*)::int from public.households), 0, 'an outsider sees no household');
select is((select count(*)::int from public.walks), 0, 'an outsider sees no walk');
select is((select count(*)::int from public.household_invites), 0, 'an outsider sees no invite token');
select throws_ok(
    $$ select public.accept_household_invite('token-expired') $$,
    '22023', 'invite not valid', 'an expired invite is refused');

-- Bruno and Chloé join -------------------------------------------------------
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000b","role":"authenticated"}', true);
set local role authenticated;
select is(public.accept_household_invite('token-bruno'),
    '11111111-1111-1111-1111-111111111111'::uuid, 'the contributor joins with his invite');
insert into public.walks (id, household_id, source, quality, started_at, ended_at, confirmed_seconds, recorded_path_meters) values
    ('33333333-3333-3333-3333-33333333333b', '11111111-1111-1111-1111-111111111111', 'gps', 'gpsRecorded',
     now() - interval '1 hour', now() - interval '30 minutes', 1800, 2140);
insert into public.walk_dogs (walk_id, dog_id, dog_name_snapshot) values
    ('33333333-3333-3333-3333-33333333333b', '22222222-2222-2222-2222-222222222222', 'Oslo');
update public.walks set confirmed_seconds = 1700 where id = '33333333-3333-3333-3333-33333333333b';
select is((select revision from public.walks where id = '33333333-3333-3333-3333-33333333333b'), 2,
    'correcting a walk moves its revision forward');
update public.walks set confirmed_seconds = 60 where id = '33333333-3333-3333-3333-33333333333a';
select is((select confirmed_seconds from public.walks where id = '33333333-3333-3333-3333-33333333333a'),
    1800::double precision, 'a contributor cannot correct someone else''s walk');
select throws_ok(
    $$ update public.walks set author_id = '00000000-0000-0000-0000-00000000000a'
       where id = '33333333-3333-3333-3333-33333333333b' $$,
    '23514', 'a walk keeps its author and household', 'a walk keeps its author');
select throws_ok(
    $$ insert into public.walks (id, household_id, source, quality, started_at, ended_at, confirmed_seconds, recorded_path_meters)
       values (gen_random_uuid(), '11111111-1111-1111-1111-111111111111', 'manual', 'manual', now() - interval '1 hour', now(), 600, 500) $$,
    '23514', null, 'a declared walk cannot carry a distance');
select throws_ok(
    $$ insert into public.walks (id, household_id, author_id, source, quality, started_at, ended_at, confirmed_seconds)
       values (gen_random_uuid(), '11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-00000000000a',
               'manual', 'manual', now() - interval '1 hour', now(), 600) $$,
    '42501', null, 'nobody records a walk in someone else''s name');
select throws_ok(
    $$ select public.accept_household_invite('token-bruno') $$,
    '22023', 'invite not valid', 'an invite is single use');

reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000c","role":"authenticated"}', true);
set local role authenticated;
select lives_ok($$ select public.accept_household_invite('token-chloe') $$, 'the reader joins');
select is((select count(*)::int from public.walks), 2, 'a reader reads the household walks');
select throws_ok(
    $$ insert into public.walks (id, household_id, source, quality, started_at, ended_at, confirmed_seconds)
       values (gen_random_uuid(), '11111111-1111-1111-1111-111111111111', 'manual', 'manual', now() - interval '1 hour', now(), 600) $$,
    '42501', null, 'a reader cannot add a walk');
select is((select count(*)::int from public.household_invites), 0, 'only owners read invites');

-- Anne, the owner, corrects any walk and removes Chloé ------------------------
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000a","role":"authenticated"}', true);
set local role authenticated;
update public.walks set confirmed_seconds = 1750 where id = '33333333-3333-3333-3333-33333333333b';
select is((select confirmed_seconds from public.walks where id = '33333333-3333-3333-3333-33333333333b'),
    1750::double precision, 'an owner may correct any walk of the household');
delete from public.household_members where user_id = '00000000-0000-0000-0000-00000000000c';
select throws_ok(
    $$ delete from public.household_members where user_id = '00000000-0000-0000-0000-00000000000a' $$,
    '23514', 'a household keeps at least one owner', 'the last owner cannot leave');

-- Chloé, removed, reads nothing any more --------------------------------------
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000c","role":"authenticated"}', true);
set local role authenticated;
select is((select count(*)::int from public.walks), 0, 'a removed member reads nothing at once');

-- Anonymous callers are not even let in ---------------------------------------
reset role;
set local role anon;
select throws_ok($$ select count(*) from public.walks $$, '42501', null, 'anonymous access is refused');
select throws_ok($$ select public.accept_household_invite('token-chloe') $$, '42501', null,
    'anonymous callers cannot accept invites');

reset role;
select * from finish();
rollback;
