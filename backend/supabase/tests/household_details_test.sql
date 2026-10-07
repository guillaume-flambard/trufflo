-- Chantier 8: walk and dog details shared with the household, planned walks,
-- daily tips, and account deletion that never takes the others' data with it.
begin;
select plan(19);

insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-00000000000a', 'anne@example.test'),
    ('00000000-0000-0000-0000-00000000000b', 'bruno@example.test'),
    ('00000000-0000-0000-0000-00000000000c', 'chloe@example.test'),
    ('00000000-0000-0000-0000-00000000000d', 'driss@example.test');

-- Anne creates the household, invites Bruno (contributor) and Chloé (reader).
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000a","role":"authenticated"}', true);
set local role authenticated;
insert into public.households (id, name) values ('11111111-1111-1111-1111-111111111111', 'Maison');
insert into public.household_invites (household_id, role, token) values
    ('11111111-1111-1111-1111-111111111111', 'contributor', 'token-bruno'),
    ('11111111-1111-1111-1111-111111111111', 'reader', 'token-chloe');
insert into public.dogs (id, household_id, name, breed_kind, size, weight_kg, traits) values
    ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111', 'Oslo', 'mixed',
     'medium', 18, array['sociable', 'calm']);
select throws_ok(
    $$ update public.dogs set traits = array['grumpy'] where id = '22222222-2222-2222-2222-222222222222' $$,
    '23514', null, 'a trait outside the declared list is refused');
select throws_ok(
    $$ update public.dogs set weight_kg = 0 where id = '22222222-2222-2222-2222-222222222222' $$,
    '23514', null, 'a weight of zero is refused');

reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000b","role":"authenticated"}', true);
set local role authenticated;
select public.accept_household_invite('token-bruno');
select lives_ok(
    $$ insert into public.walks (id, household_id, source, quality, started_at, ended_at, confirmed_seconds,
                                 recorded_path_meters, title, mood, weather, temperature_c)
       values ('33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111', 'gps',
               'gpsRecorded', now() - interval '42 minutes', now(), 2520, 2140,
               'Balade dans le quartier', 'great', 'sunny', 18) $$,
    'a contributor shares a walk with its title, mood and weather');
select throws_ok(
    $$ update public.walks set mood = 'ecstatic' where id = '33333333-3333-3333-3333-333333333333' $$,
    '23514', null, 'a mood outside the list is refused');
select lives_ok(
    $$ insert into public.planned_walks (id, household_id, planned_at, place_name)
       values ('44444444-4444-4444-4444-444444444444', '11111111-1111-1111-1111-111111111111',
               now() + interval '1 day', 'Parc des Buttes-Chaumont') $$,
    'a contributor plans a walk');
select is((select size || ',' || weight_kg::text || ',' || array_to_string(traits, '+')
           from public.dogs where id = '22222222-2222-2222-2222-222222222222'),
          'medium,18,sociable+calm', 'a member reads the declared dog details');

reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000c","role":"authenticated"}', true);
set local role authenticated;
select public.accept_household_invite('token-chloe');
select is((select title || ' / ' || mood from public.walks), 'Balade dans le quartier / great',
          'a reader sees the walk title and mood');
select is((select count(*)::int from public.planned_walks), 1, 'a reader sees the planned walk');
select throws_ok(
    $$ insert into public.planned_walks (id, household_id, planned_at)
       values ('55555555-5555-5555-5555-555555555555', '11111111-1111-1111-1111-111111111111', now()) $$,
    '42501', null, 'a reader cannot plan a walk');
update public.planned_walks set place_name = 'Ailleurs';
select is((select place_name from public.planned_walks), 'Parc des Buttes-Chaumont',
          'a reader cannot change someone else''s plan');

reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000d","role":"authenticated"}', true);
set local role authenticated;
select is((select count(*)::int from public.planned_walks), 0, 'an outsider sees no planned walk');

-- Tips: everyone, even without an account, reads the active ones.
reset role;
set local role anon;
select is((select count(*)::int from public.daily_tips), 7, 'anon reads the seven tips');
select throws_ok($$ insert into public.daily_tips (title, body, position) values ('x', 'y', 99) $$,
    '42501', null, 'anon cannot write a tip');

-- Account deletion. Bruno (not an owner) deletes his account: his own walk
-- goes, the household and Oslo stay.
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000a","role":"authenticated"}', true);
set local role authenticated;
-- Make Bruno the last editor of Oslo, so the cascade would bite without the hand-over.
reset role;
update public.dogs set updated_by = '00000000-0000-0000-0000-00000000000b';
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000b","role":"authenticated"}', true);
set local role authenticated;
select lives_ok($$ select public.delete_my_account() $$, 'a member deletes their account');
reset role;
select is((select count(*)::int from auth.users where id = '00000000-0000-0000-0000-00000000000b'), 0,
          'the account is gone');
select is((select count(*)::int from public.dogs where id = '22222222-2222-2222-2222-222222222222'), 1,
          'the household''s dog survives the last editor''s deletion');

-- Anne is the only owner and Chloé remains: deletion is refused until she
-- names another owner.
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000a","role":"authenticated"}', true);
set local role authenticated;
select throws_ok($$ select public.delete_my_account() $$, '23514', 'name another owner first',
    'the last owner of a shared household cannot vanish');
update public.household_members set role = 'owner'
where user_id = '00000000-0000-0000-0000-00000000000c';
select lives_ok($$ select public.delete_my_account() $$, 'once another owner exists, she can');
reset role;
select is((select count(*)::int from public.households), 1,
          'the household she created stays for the remaining owner');

select * from finish();
rollback;
