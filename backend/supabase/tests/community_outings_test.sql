-- Community walk outings (lot C, ADR 0010), played by seven people in the
-- seeded Paris zone and one other zone:
--   Léa (organizer, registered by hand), Camille, Sam and Alex (members of
--   Paris), Zoé (member of another zone), Nina (no profile), Ugo (suspended).
-- Every check runs as that person, under RLS, through the grants the app
-- uses and the calls SupabaseCommunityRemote.swift makes. The rules are those
-- of InMemoryCommunityServer.swift and truffloTests/CommunityRulesTests.swift.
-- The concurrent last place lives in community_last_place_race_test.sql.
begin;
select plan(105);

insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-0000000000e1', 'lea@example.test'),
    ('00000000-0000-0000-0000-0000000000e2', 'camille@example.test'),
    ('00000000-0000-0000-0000-0000000000e3', 'sam@example.test'),
    ('00000000-0000-0000-0000-0000000000e4', 'alex@example.test'),
    ('00000000-0000-0000-0000-0000000000e5', 'zoe@example.test'),
    ('00000000-0000-0000-0000-0000000000e6', 'nina@example.test'),
    ('00000000-0000-0000-0000-0000000000e7', 'ugo@example.test');
insert into public.community_zones (id, name, is_open) values
    ('lyon-6', 'Lyon 6e', true),
    ('ferme', 'Zone fermée', false);

-- What the server holds, and what it must never hold ---------------------------
select is((select count(*)::int from information_schema.columns
           where table_schema = 'public'
             and table_name in ('community_zones', 'community_profiles', 'community_dogs', 'community_organizers',
                                'community_moderators', 'outings', 'outing_participants', 'outing_dogs',
                                'outing_updates', 'reports', 'blocks')
             and column_name ~ '(lat|lon|lng|coord|track|location|geo|address)'),
          0, 'no coordinate, track or address on any community table');
select is((select name || ':' || is_open from public.community_zones where id = 'paris'), 'Paris:true',
          'the pilot zone, Paris, is seeded open (D5)');
select is((select count(*)::int from public.community_moderators), 0,
          'no moderator is seeded: the id is added by hand (D6)');
select ok((select bool_and(c.relrowsecurity) from pg_class c join pg_namespace n on n.oid = c.relnamespace
           where n.nspname = 'public' and c.relkind = 'r'
             and c.relname in ('community_zones', 'community_profiles', 'community_dogs', 'community_organizers',
                               'community_moderators', 'outings', 'outing_participants', 'outing_dogs',
                               'outing_updates', 'reports', 'blocks')),
          'row level security is on for every community table');
select is((select count(*)::int from pg_class c join pg_namespace n on n.oid = c.relnamespace
           where n.nspname = 'public' and c.relname in ('visible_outings', 'my_outings', 'my_blocks')
             and 'security_invoker=true' = any (c.reloptions)),
          3, 'the three views run with the caller''s rights');

-- Grants: exactly what the client calls ----------------------------------------
select is(
    (select string_agg(line, ' | ' order by line)
     from (select (g.table_name::text || ':' || string_agg(g.privilege_type::text, ',' order by g.privilege_type::text)) collate "C" as line
           from information_schema.role_table_grants g
           where g.grantee = 'authenticated' and g.table_schema = 'public'
             and g.table_name in ('community_zones', 'community_profiles', 'community_dogs', 'community_organizers',
                                  'community_moderators', 'outings', 'outing_participants', 'outing_dogs',
                                  'outing_updates', 'reports', 'blocks', 'visible_outings', 'my_outings', 'my_blocks')
           group by g.table_name::text) t),
    ('blocks:SELECT | community_dogs:INSERT,SELECT,UPDATE | community_organizers:SELECT'
     || ' | community_profiles:SELECT | community_zones:SELECT | my_blocks:SELECT | my_outings:SELECT'
     || ' | outings:SELECT | reports:SELECT | visible_outings:SELECT') collate "C",
    'authenticated reads the community through these objects only, writes only its dogs directly');
select is((select count(*)::int from information_schema.role_table_grants
           where grantee = 'anon' and table_schema = 'public'
             and table_name in ('community_zones', 'community_profiles', 'community_dogs', 'community_organizers',
                                'community_moderators', 'outings', 'outing_participants', 'outing_dogs',
                                'outing_updates', 'reports', 'blocks', 'visible_outings', 'my_outings', 'my_blocks')),
          0, 'anon holds nothing on the community');
select is((select count(*)::int from unnest(array[
              'public.save_profile(text, text, boolean)', 'public.request_to_join(uuid, uuid[])',
              'public.decide_request(uuid, uuid, boolean)', 'public.withdraw(uuid)',
              'public.declare_attendance(uuid, boolean)',
              'public.create_outing(text, timestamptz, integer, text, text, integer, integer)',
              'public.update_outing(uuid, timestamptz, text)', 'public.cancel_outing(uuid)',
              'public.list_participants(uuid)', 'public.list_outing_updates(uuid)',
              'public.report(text, uuid, text, text)', 'public.block(uuid)', 'public.unblock(uuid)']) f
           where has_function_privilege('authenticated', f, 'execute')
             and not has_function_privilege('anon', f, 'execute')),
          13, 'the thirteen functions are callable by authenticated and not by anon');

-- Anon reaches nothing --------------------------------------------------------
set local role anon;
select throws_ok($$ select count(*) from public.community_zones $$, '42501', null, 'anon reads no zone');
select throws_ok($$ select count(*) from public.visible_outings $$, '42501', null, 'anon reads no outing');
select throws_ok($$ select public.request_to_join('00000000-0000-0000-0000-000000000000', '{}') $$,
                 '42501', null, 'anon calls no community function');
reset role;

-- Profiles --------------------------------------------------------------------
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e6","role":"authenticated"}', true);
set local role authenticated;
select is((select string_agg(id, ',' order by name) from public.community_zones), 'lyon-6,paris',
          'open zones are listed before any profile, the closed one is not');
select throws_ok($$ select public.save_profile('Nina', 'paris', false) $$, '42501', null,
                 'no profile without the adult declaration');
select throws_ok($$ select public.save_profile('Nina', 'ferme', true) $$, '42501', null,
                 'no profile in a closed zone');
select throws_ok($$ select public.save_profile('   ', 'paris', true) $$, '23514', null,
                 'a blank name is refused');
select is((select count(*)::int from public.community_profiles), 0, 'Nina still has no profile');
select is((select count(*)::int from public.visible_outings), 0, 'without a profile, no outing');
select throws_ok($$ select public.report('outing', '00000000-0000-0000-0000-000000000000', 'spam', '') $$,
                 'P0001', 'no profile', 'without a profile, no report');

reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e1","role":"authenticated"}', true);
set local role authenticated;
select public.save_profile('Léa', 'paris', true);
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e2","role":"authenticated"}', true);
set local role authenticated;
select lives_ok($$ select public.save_profile('  Camille ', 'paris', true) $$, 'an adult creates a profile');
select is((select display_name || '@' || zone_id from public.community_profiles), 'Camille@paris',
          'a person reads their own profile, name trimmed');
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e3","role":"authenticated"}', true);
set local role authenticated;
select public.save_profile('Sam', 'paris', true);
select is((select count(*)::int from public.community_profiles), 1, 'nobody reads someone else''s profile');
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e4","role":"authenticated"}', true);
set local role authenticated;
select public.save_profile('Alex', 'paris', true);
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e5","role":"authenticated"}', true);
set local role authenticated;
select public.save_profile('Zoé', 'lyon-6', true);
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e7","role":"authenticated"}', true);
set local role authenticated;
select public.save_profile('Ugo', 'paris', true);
reset role;

-- The adult declaration is stamped once, never rewritten.
update public.community_profiles set adult_declared_at = '2026-01-01T00:00:00Z'
where user_id = '00000000-0000-0000-0000-0000000000e2';
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e2","role":"authenticated"}', true);
set local role authenticated;
select public.save_profile('Camille', 'paris', true);
select is((select adult_declared_at from public.community_profiles), '2026-01-01T00:00:00Z'::timestamptz,
          'saving the profile again keeps the first adult declaration');
reset role;

-- Organizers are registered by hand ---------------------------------------------
insert into public.community_organizers (user_id, zone_id) values ('00000000-0000-0000-0000-0000000000e1', 'paris');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e2","role":"authenticated"}', true);
set local role authenticated;
select is((select count(*)::int from public.community_organizers where zone_id = 'paris'), 0,
          'Camille is not an organizer');
select throws_ok(
    $$ select public.create_outing('paris', now() + interval '1 day', 60, 'Parc', '', 4, 4) $$,
    '42501', null, 'only a registered organizer creates an outing');
select throws_ok($$ insert into public.outings (organizer_id, zone_id, starts_at, duration_minutes, meeting_point,
                                               human_capacity, dog_capacity)
                    values ('00000000-0000-0000-0000-0000000000e2', 'paris', now() + interval '1 day', 60, 'Parc', 4, 4) $$,
                 '42501', null, 'nobody writes an outing directly');
-- Camille shows her dog Oslo; she cannot show one in Sam's name.
select lives_ok($$ insert into public.community_dogs (id, owner_id, name)
                   values ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000e2', 'Oslo') $$,
                'a member shows one of her dogs');
select throws_ok($$ insert into public.community_dogs (id, owner_id, name)
                    values (gen_random_uuid(), '00000000-0000-0000-0000-0000000000e3', 'Faux') $$,
                 '42501', null, 'nobody shows a dog in someone else''s name');
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e3","role":"authenticated"}', true);
set local role authenticated;
insert into public.community_dogs (id, owner_id, name)
values ('00000000-0000-0000-0000-0000000000d2', '00000000-0000-0000-0000-0000000000e3', 'Pixel');
select is((select string_agg(name, ',') from public.community_dogs), 'Pixel', 'a member reads only her own dogs');
reset role;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e1","role":"authenticated"}', true);
set local role authenticated;
select is((select count(*)::int from public.community_organizers where zone_id = 'paris'), 1,
          'Léa reads that she organizes in Paris');
select throws_ok(
    $$ select public.create_outing('paris', now() - interval '1 hour', 60, 'Parc', '', 4, 4) $$,
    '23514', null, 'an outing starts in the future');
select throws_ok(
    $$ select public.create_outing('paris', now() + interval '1 day', 60, 'Parc', '', 31, 4) $$,
    '23514', null, 'no more than 30 places');
select throws_ok(
    $$ select public.create_outing('lyon-6', now() + interval '1 day', 60, 'Parc', '', 4, 4) $$,
    '42501', null, 'an organizer proposes only in the zone she was registered for');
select set_config('t.o1', public.create_outing('paris', now() + interval '1 day', 60, 'Entrée nord du parc',
                                                'En laisse près de l''étang', 3, 3)::text, true);
select set_config('t.o2', public.create_outing('paris', now() + interval '2 days', 45, 'Place de la mairie', '', 1, 5)::text, true);
select set_config('t.o3', public.create_outing('paris', now() + interval '3 days', 90, 'Bords du canal', '', 5, 1)::text, true);
select is((select count(*)::int from public.my_outings), 3, 'the organizer finds her outings in my_outings');
reset role;

-- Who sees what (C-AC-01) -------------------------------------------------------
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e4","role":"authenticated"}', true);
set local role authenticated;
select is((select organizer_name || '|' || meeting_point || '|' || humans_accepted || '|' || coalesce(my_status, 'none')
           from public.visible_outings where id = current_setting('t.o1')::uuid),
          'Léa|Entrée nord du parc|0|none', 'a member of the zone sees its published outing, with counts only');
select is((select count(*)::int from public.visible_outings where zone_id = 'paris'), 3,
          'a member of the zone sees the three outings');
select throws_ok($$ select * from public.list_participants(current_setting('t.o1')::uuid) $$,
                 '42501', null, 'a stranger to the outing does not see its participants');
select throws_ok($$ select count(*) from public.outing_participants $$, '42501', null,
                 'nobody reads the participants flat');
select throws_ok($$ select count(*) from public.outing_updates $$, '42501', null,
                 'nobody reads the updates flat');
select is((select count(*)::int from public.my_outings), 0, 'Alex has no outing of her own yet');
reset role;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e5","role":"authenticated"}', true);
set local role authenticated;
select is((select count(*)::int from public.visible_outings), 0, 'another zone sees no Paris outing');
select is((select count(*)::int from public.outings), 0, 'nor through the table');
select throws_ok($$ select public.request_to_join(current_setting('t.o1')::uuid, '{}') $$,
                 'P0001', 'outing gone', 'and cannot ask to join it');
reset role;

update public.community_profiles set suspended_at = now() where user_id = '00000000-0000-0000-0000-0000000000e7';
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e7","role":"authenticated"}', true);
set local role authenticated;
select is((select count(*)::int from public.visible_outings), 0, 'a suspended profile sees nothing');
select isnt((select suspended_at from public.community_profiles), null,
            'but reads its own suspension, so the app can tell');
select throws_ok($$ select public.request_to_join(current_setting('t.o1')::uuid, '{}') $$,
                 'P0001', 'no profile', 'a suspended profile does nothing');
reset role;

-- Requests, decisions -----------------------------------------------------------
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e2","role":"authenticated"}', true);
set local role authenticated;
select lives_ok($$ select public.request_to_join(current_setting('t.o1')::uuid, '{00000000-0000-0000-0000-0000000000d1}') $$,
                'Camille asks to come with Oslo');
select is((select my_status from public.visible_outings where id = current_setting('t.o1')::uuid), 'requested',
          'her request is pending');
select is((select my_status from public.my_outings where id = current_setting('t.o1')::uuid), 'requested',
          'and listed in her outings');
select throws_ok($$ select public.request_to_join(current_setting('t.o2')::uuid, '{00000000-0000-0000-0000-0000000000d2}') $$,
                 '42501', null, 'nobody announces someone else''s dog');
select throws_ok($$ select * from public.list_participants(current_setting('t.o1')::uuid) $$,
                 '42501', null, 'a pending request does not show the participants');
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e3","role":"authenticated"}', true);
set local role authenticated;
select public.request_to_join(current_setting('t.o1')::uuid, '{00000000-0000-0000-0000-0000000000d2}');
select throws_ok($$ select public.decide_request(current_setting('t.o1')::uuid, '00000000-0000-0000-0000-0000000000e2', true) $$,
                 '42501', null, 'a participant does not decide');
reset role;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e1","role":"authenticated"}', true);
set local role authenticated;
select throws_ok($$ select public.request_to_join(current_setting('t.o1')::uuid, '{}') $$,
                 '42501', null, 'the organizer does not ask to join her own outing');
select is((select string_agg(display_name || ':' || status, ',' order by display_name)
           from public.list_participants(current_setting('t.o1')::uuid)),
          'Camille:requested,Sam:requested', 'the organizer sees every request');
select lives_ok($$ select public.decide_request(current_setting('t.o1')::uuid, '00000000-0000-0000-0000-0000000000e2', true) $$,
                'the organizer accepts Camille');
select lives_ok($$ select public.decide_request(current_setting('t.o1')::uuid, '00000000-0000-0000-0000-0000000000e3', false) $$,
                'and declines Sam');
select throws_ok($$ select public.decide_request(current_setting('t.o1')::uuid, '00000000-0000-0000-0000-0000000000e3', true) $$,
                 '42501', null, 'a decided request is not decided again');
select is((select string_agg(display_name || ':' || status, ',' order by display_name)
           from public.list_participants(current_setting('t.o1')::uuid)),
          'Camille:accepted,Sam:declined', 'the organizer sees both decisions');
reset role;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e2","role":"authenticated"}', true);
set local role authenticated;
select is((select string_agg(display_name || ':' || array_to_string(dog_names, '+') || ':' || coalesce(attended::text, 'hidden'), ',')
           from public.list_participants(current_setting('t.o1')::uuid)),
          'Camille:Oslo:hidden', 'an accepted person sees the accepted ones and their dogs, not the declined, not attendance');
select is((select humans_accepted || '/' || dogs_accepted from public.visible_outings where id = current_setting('t.o1')::uuid),
          '1/1', 'one person and one dog take places');
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e3","role":"authenticated"}', true);
set local role authenticated;
select lives_ok($$ select public.request_to_join(current_setting('t.o1')::uuid, '{}') $$,
                'after a refusal, Sam may ask again');
select is((select my_status from public.visible_outings where id = current_setting('t.o1')::uuid), 'requested',
          'his new request is pending');
reset role;

-- Capacity: people and dogs are two checks (C-AC-05, sequential) --------------------
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e2","role":"authenticated"}', true);
set local role authenticated;
select public.request_to_join(current_setting('t.o2')::uuid, '{}');
select public.request_to_join(current_setting('t.o3')::uuid, '{00000000-0000-0000-0000-0000000000d1}');
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e3","role":"authenticated"}', true);
set local role authenticated;
select public.request_to_join(current_setting('t.o2')::uuid, '{}');
select public.request_to_join(current_setting('t.o3')::uuid, '{00000000-0000-0000-0000-0000000000d2}');
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e1","role":"authenticated"}', true);
set local role authenticated;
select lives_ok($$ select public.decide_request(current_setting('t.o2')::uuid, '00000000-0000-0000-0000-0000000000e2', true) $$,
                'the last human place goes to Camille');
select throws_ok($$ select public.decide_request(current_setting('t.o2')::uuid, '00000000-0000-0000-0000-0000000000e3', true) $$,
                 'P0001', 'outing full', 'accepting beyond the human capacity is refused');
select lives_ok($$ select public.decide_request(current_setting('t.o3')::uuid, '00000000-0000-0000-0000-0000000000e2', true) $$,
                'the last dog place goes to Oslo');
select throws_ok($$ select public.decide_request(current_setting('t.o3')::uuid, '00000000-0000-0000-0000-0000000000e3', true) $$,
                 'P0001', 'outing full', 'accepting beyond the dog capacity is refused');
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e4","role":"authenticated"}', true);
set local role authenticated;
select is((select human_capacity - humans_accepted from public.visible_outings where id = current_setting('t.o2')::uuid),
          0, 'a member of the zone sees no place left');
reset role;

-- Withdrawing frees the place.
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e2","role":"authenticated"}', true);
set local role authenticated;
select lives_ok($$ select public.withdraw(current_setting('t.o2')::uuid) $$, 'Camille withdraws');
select is((select my_status from public.my_outings where id = current_setting('t.o2')::uuid), 'withdrawn',
          'her outing says she withdrew');
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e4","role":"authenticated"}', true);
set local role authenticated;
select is((select humans_accepted from public.visible_outings where id = current_setting('t.o2')::uuid),
          0, 'withdrawing frees the place');
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e1","role":"authenticated"}', true);
set local role authenticated;
select lives_ok($$ select public.decide_request(current_setting('t.o2')::uuid, '00000000-0000-0000-0000-0000000000e3', true) $$,
                'the freed place can be given to Sam');

-- Changes of time and place (C-AC-04) --------------------------------------------
select lives_ok($$ select public.update_outing(current_setting('t.o1')::uuid, now() + interval '25 hours', 'Sortie ouest du parc') $$,
                'the organizer moves the time and the place');
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e2","role":"authenticated"}', true);
set local role authenticated;
select is((select string_agg(kind, ',' order by kind) from public.list_outing_updates(current_setting('t.o1')::uuid)),
          'place,time', 'the accepted participant sees both changes');
select is((select current from public.list_outing_updates(current_setting('t.o1')::uuid) where kind = 'place'),
          'Sortie ouest du parc', 'with the new place');
select is((select meeting_point from public.visible_outings where id = current_setting('t.o1')::uuid),
          'Sortie ouest du parc', 'and the outing itself moved');
select throws_ok($$ select public.update_outing(current_setting('t.o1')::uuid, now() + interval '2 days', 'Ailleurs') $$,
                 '42501', null, 'a participant does not change the outing');
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e3","role":"authenticated"}', true);
set local role authenticated;
select is((select count(*)::int from public.list_outing_updates(current_setting('t.o1')::uuid)), 2,
          'a pending request sees the changes too');
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e4","role":"authenticated"}', true);
set local role authenticated;
select throws_ok($$ select * from public.list_outing_updates(current_setting('t.o1')::uuid) $$,
                 '42501', null, 'someone with no request does not');
reset role;

-- Cancellation ----------------------------------------------------------------
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e2","role":"authenticated"}', true);
set local role authenticated;
select throws_ok($$ select public.cancel_outing(current_setting('t.o3')::uuid) $$, '42501', null,
                 'a participant does not cancel');
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e1","role":"authenticated"}', true);
set local role authenticated;
select lives_ok($$ select public.cancel_outing(current_setting('t.o3')::uuid) $$, 'the organizer cancels');
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e2","role":"authenticated"}', true);
set local role authenticated;
select is((select count(*)::int from public.visible_outings where id = current_setting('t.o3')::uuid), 0,
          'a cancelled outing leaves the zone''s list');
select is((select status from public.my_outings where id = current_setting('t.o3')::uuid), 'cancelled',
          'and stays in the participant''s outings, marked cancelled');
select is((select kind from public.list_outing_updates(current_setting('t.o3')::uuid)), 'cancelled',
          'with a cancellation update');
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e4","role":"authenticated"}', true);
set local role authenticated;
select throws_ok($$ select public.request_to_join(current_setting('t.o3')::uuid, '{}') $$,
                 'P0001', 'outing gone', 'a cancelled outing cannot be joined');
reset role;

-- Attendance is not the inscription (C-AC-06) -----------------------------------
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e2","role":"authenticated"}', true);
set local role authenticated;
select throws_ok($$ select public.declare_attendance(current_setting('t.o1')::uuid, true) $$,
                 '42501', null, 'no attendance before the outing is over');
reset role;
-- An outing that ended two hours ago, written as the past would have left it.
insert into public.outings (id, organizer_id, zone_id, starts_at, duration_minutes, meeting_point, human_capacity, dog_capacity)
values ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000e1', 'paris',
        now() - interval '3 hours', 60, 'Quai de la Seine', 5, 5);
insert into public.outing_participants (outing_id, user_id, status) values
    ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000e2', 'accepted'),
    ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000e4', 'requested');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e2","role":"authenticated"}', true);
set local role authenticated;
select lives_ok($$ select public.declare_attendance('00000000-0000-0000-0000-0000000000f1', false) $$,
                'an accepted person declares, after the outing, that she did not come');
select is((select my_status || ':' || my_attended from public.my_outings where id = '00000000-0000-0000-0000-0000000000f1'),
          'accepted:false', 'her inscription stays accepted, her attendance is apart');
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e4","role":"authenticated"}', true);
set local role authenticated;
select throws_ok($$ select public.declare_attendance('00000000-0000-0000-0000-0000000000f1', true) $$,
                 '42501', null, 'someone never accepted declares no attendance');
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e1","role":"authenticated"}', true);
set local role authenticated;
select is((select status || ':' || attended from public.list_participants('00000000-0000-0000-0000-0000000000f1')
           where display_name = 'Camille'),
          'accepted:false', 'the organizer sees the inscription and the attendance as two states');
reset role;

-- Reports ---------------------------------------------------------------------
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e4","role":"authenticated"}', true);
set local role authenticated;
select lives_ok($$ select public.report('outing', current_setting('t.o1')::uuid, 'danger', 'Chien agressif annoncé') $$,
                'a member reports an outing');
select throws_ok($$ select public.report('outing', current_setting('t.o1')::uuid, 'boring', '') $$,
                 '23514', null, 'an unknown reason is refused');
select is((select count(*)::int from public.reports), 0, 'a member does not read reports');
reset role;
insert into public.community_moderators (user_id) values ('00000000-0000-0000-0000-0000000000e5');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e5","role":"authenticated"}', true);
set local role authenticated;
select is((select reason || ':' || detail from public.reports), 'danger:Chien agressif annoncé',
          'a moderator reads the report');
reset role;

-- Blocks, both ways, at once (C-AC-08) -----------------------------------------
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e4","role":"authenticated"}', true);
set local role authenticated;
select lives_ok($$ select public.block('00000000-0000-0000-0000-0000000000e1') $$, 'Alex blocks Léa');
select is((select count(*)::int from public.visible_outings), 0, 'the blocker no longer sees her outings');
select throws_ok($$ select public.request_to_join(current_setting('t.o1')::uuid, '{}') $$,
                 'P0001', 'blocked', 'and cannot ask to join them');
select is((select string_agg(display_name, ',') from public.my_blocks), 'Léa', 'Alex finds Léa in her blocks');
select throws_ok($$ select public.block('00000000-0000-0000-0000-0000000000e4') $$, '42501', null,
                 'nobody blocks themselves');
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e1","role":"authenticated"}', true);
set local role authenticated;
select is((select count(*)::int from public.my_blocks), 0, 'the blocked person is not told');
select lives_ok($$ select public.block('00000000-0000-0000-0000-0000000000e3') $$, 'Léa blocks Sam');
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e3","role":"authenticated"}', true);
set local role authenticated;
select is((select count(*)::int from public.visible_outings), 0, 'the blocked person no longer sees the blocker''s outings');
select is((select count(*)::int from public.outings where status = 'published' and organizer_id = '00000000-0000-0000-0000-0000000000e1'
             and id not in (select id from public.my_outings)),
          0, 'nor through the table');
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e4","role":"authenticated"}', true);
set local role authenticated;
select lives_ok($$ select public.unblock('00000000-0000-0000-0000-0000000000e1') $$, 'Alex lifts her block');
select is((select count(*)::int from public.visible_outings), 3, 'and sees the published outings again, yesterday''s included');
select is((select count(*)::int from public.my_blocks), 0, 'her block list is empty');
reset role;
select is((select count(*)::int from public.blocks where lifted_at is not null), 1,
          'a lifted block is tombstoned, not deleted');

select * from finish();
rollback;
