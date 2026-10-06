-- Member names (PRD F08): a member names themselves, every member reads the
-- names, nobody renames someone else, a removed member's name goes with them.
begin;
select plan(7);

insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-00000000000a', 'anne@example.test'),
    ('00000000-0000-0000-0000-00000000000b', 'bruno@example.test'),
    ('00000000-0000-0000-0000-00000000000d', 'driss@example.test');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000a","role":"authenticated"}', true);
set local role authenticated;
insert into public.households (id, name) values ('11111111-1111-1111-1111-111111111111', 'Maison');
insert into public.household_invites (household_id, role, token) values
    ('11111111-1111-1111-1111-111111111111', 'reader', 'token-bruno');
insert into public.member_profiles (household_id, user_id, display_name) values
    ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-00000000000a', 'Anne');

reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000b","role":"authenticated"}', true);
set local role authenticated;
select public.accept_household_invite('token-bruno');
select lives_ok(
    $$ insert into public.member_profiles (household_id, user_id, display_name)
       values ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-00000000000b', 'Bruno') $$,
    'a reader names themselves');
select is((select count(*)::int from public.member_profiles), 2, 'a member reads every name of the household');
select throws_ok(
    $$ insert into public.member_profiles (household_id, user_id, display_name)
       values ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-00000000000a', 'Pas Anne')
       on conflict (household_id, user_id) do update set display_name = excluded.display_name $$,
    '42501', null, 'nobody renames someone else');
select throws_ok(
    $$ insert into public.member_profiles (household_id, user_id, display_name)
       values ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-00000000000b', '   ')
       on conflict (household_id, user_id) do update set display_name = excluded.display_name $$,
    '23514', null, 'a blank name is refused');

reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000d","role":"authenticated"}', true);
set local role authenticated;
select is((select count(*)::int from public.member_profiles), 0, 'an outsider reads no name');
select throws_ok(
    $$ insert into public.member_profiles (household_id, user_id, display_name)
       values ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-00000000000d', 'Driss') $$,
    '42501', null, 'an outsider cannot name themselves into a household');

-- Bruno leaves: his name goes with his membership.
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000b","role":"authenticated"}', true);
set local role authenticated;
delete from public.household_members where user_id = '00000000-0000-0000-0000-00000000000b';
reset role;
select is((select count(*)::int from public.member_profiles
           where user_id = '00000000-0000-0000-0000-00000000000b'), 0,
          'a member who leaves takes their name with them');

select * from finish();
rollback;
