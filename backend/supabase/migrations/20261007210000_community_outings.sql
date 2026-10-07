-- Lot C, PRD F09 F10 F11 F13: community walk outings ("sorties"), ADR 0010.
--
-- An outing is a future meeting in a public place of a zone, proposed by an
-- organizer registered by hand. People ask to come, the organizer accepts or
-- declines, the server holds the capacity. The client contract (names,
-- columns, error strings) is ADR 0010 « Contrat client »; the behaviour is
-- the one InMemoryCommunityServer.swift executes in the app's tests.
--
-- What is deliberately absent (ADR 0010 « Ce qui n'est pas dans ce modèle »):
--   * no coordinate of anyone, no track, no map of people: the meeting point
--     is a text the organizer types, the zone is chosen by the person;
--   * no link to the household (`dogs`, `walks`): community dogs are a
--     voluntary projection, written by the person for this purpose only;
--   * no messaging: an organizer's change of time or place is a structured
--     `outing_updates` row, nothing else is said through the server.
--
-- How rights work, as for the household:
--   * every table has row level security; nobody reads participants "flat":
--     `outing_participants`, `outing_dogs` and `outing_updates` carry no
--     privilege at all for the app's role, and are only read through
--     functions that decide who may see which row;
--   * every write that carries a rule (request, decision, capacity, block)
--     goes through a SECURITY DEFINER function in the unexposed `private`
--     schema that only ever acts for auth.uid(), behind a SECURITY INVOKER
--     wrapper in `public`, the only thing PostgREST exposes;
--   * the views are `security_invoker`, so the caller's own RLS on `outings`
--     and `blocks` applies under them (PostgreSQL 15+, the local stack and
--     production run 17).
--
-- Errors the client recognises by their text (CommunityError(serverMessage:)):
-- 'outing full', 'outing gone', 'blocked', 'no profile', 'not allowed'.
-- SQLSTATE 42501 is mapped to "not allowed" by the client whatever the text,
-- so only the 'not allowed' refusals use it; the others keep the default
-- P0001, or the client would lose their meaning.
--
-- Deletions are tombstones (DATA-CONTRACTS §8): a dog is retired with
-- `deleted_at`, a block is lifted with `lifted_at`, an announced dog is
-- withdrawn from an outing with `retracted_at`. Nothing here deletes a row,
-- which also keeps this file acceptable to tools/backend/apply-migration.sh.
--
-- Moderation (decision D6, Guillaume): `community_moderators` is created
-- empty, since no real user id is known here. To name a moderator, as
-- postgres on the database, once the person has signed in once:
--     insert into public.community_moderators (user_id)
--     select id from auth.users where email = '<the account email>';
-- Organizers are registered the same way, by hand (PRD F09):
--     insert into public.community_organizers (user_id, zone_id, added_by)
--     values ('<organizer uuid>', 'paris', '<moderator uuid>');
-- Suspending a profile is `update public.community_profiles set
-- suspended_at = now() where user_id = ...`; removing an outing is
-- `update public.outings set status = 'removed' where id = ...`.

create schema if not exists private;

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

-- Written by migrations only. A closed zone shows nothing.
create table public.community_zones (
    id text primary key check (id ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and char_length(id) <= 40),
    name text not null check (char_length(btrim(name)) between 1 and 80),
    is_open boolean not null default false
);

-- Decision D5 (2026-10-07): the pilot opens in Paris, one city.
insert into public.community_zones (id, name, is_open) values ('paris', 'Paris', true);

-- What the person chooses to show. Never a copy of the household profile.
-- adult_declared_at is the pilot's adults-only statement (C-REQ-10): it is
-- stamped once, the first time, and never rewritten.
create table public.community_profiles (
    user_id uuid primary key references auth.users (id) on delete cascade,
    display_name text not null check (char_length(btrim(display_name)) between 1 and 40),
    zone_id text not null references public.community_zones (id),
    adult_declared_at timestamptz not null,
    created_at timestamptz not null default now(),
    -- Set by a moderator: the profile then reads and writes nothing.
    suspended_at timestamptz
);
create index community_profiles_zone_idx on public.community_profiles (zone_id);

-- The dogs a person shows. The id is the client's UUID (it upserts).
create table public.community_dogs (
    id uuid primary key,
    owner_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
    name text not null check (char_length(btrim(name)) between 1 and 40),
    breed_label text not null default '' check (char_length(breed_label) <= 80),
    public_note text not null default '' check (char_length(public_note) <= 200),
    created_at timestamptz not null default now(),
    deleted_at timestamptz
);
create index community_dogs_owner_idx on public.community_dogs (owner_id);

-- Moderators, written by hand (D6). Empty on purpose: see the header.
create table public.community_moderators (
    user_id uuid primary key references auth.users (id) on delete cascade,
    added_at timestamptz not null default now()
);

-- Who may propose outings in a zone (PRD F09, "contrôlées manuellement").
create table public.community_organizers (
    user_id uuid not null references auth.users (id) on delete cascade,
    zone_id text not null references public.community_zones (id),
    added_at timestamptz not null default now(),
    added_by uuid references auth.users (id) on delete set null,
    primary key (user_id, zone_id)
);

create table public.outings (
    id uuid primary key default gen_random_uuid(),
    organizer_id uuid not null references auth.users (id) on delete cascade,
    zone_id text not null references public.community_zones (id),
    starts_at timestamptz not null,
    duration_minutes integer not null check (duration_minutes between 15 and 240),
    -- A public place, typed by the organizer. Never a coordinate.
    meeting_point text not null check (char_length(btrim(meeting_point)) between 1 and 120),
    rules text not null default '' check (char_length(rules) <= 500),
    human_capacity integer not null check (human_capacity between 1 and 30),
    dog_capacity integer not null check (dog_capacity between 1 and 30),
    -- removed = taken down by moderation.
    status text not null default 'published' check (status in ('published', 'cancelled', 'removed')),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);
create index outings_zone_starts_idx on public.outings (zone_id, starts_at);
create index outings_organizer_idx on public.outings (organizer_id);

-- Inscription (status) and attendance (attended) are two columns, never one
-- state (PRD F10, C-AC-06).
create table public.outing_participants (
    outing_id uuid not null references public.outings (id) on delete cascade,
    user_id uuid not null references auth.users (id) on delete cascade,
    status text not null check (status in ('requested', 'accepted', 'declined', 'withdrawn')),
    requested_at timestamptz not null default now(),
    decided_at timestamptz,
    attended boolean,
    attended_declared_at timestamptz,
    primary key (outing_id, user_id)
);
create index outing_participants_user_idx on public.outing_participants (user_id);
create index outing_participants_status_idx on public.outing_participants (outing_id, status);

-- The dogs announced with a request, taken from the person's own dogs. A new
-- request after a refusal or a withdrawal replaces them: the old ones are
-- tombstoned, not deleted.
create table public.outing_dogs (
    outing_id uuid not null,
    user_id uuid not null,
    dog_id uuid not null references public.community_dogs (id) on delete cascade,
    announced_at timestamptz not null default now(),
    retracted_at timestamptz,
    primary key (outing_id, user_id, dog_id),
    foreign key (outing_id, user_id)
        references public.outing_participants (outing_id, user_id) on delete cascade
);

-- What the registered see when the organizer changes the time or the place,
-- or cancels. Not a messaging channel. `previous` and `current` are display
-- texts: times are written in Paris time, the pilot's only zone.
create table public.outing_updates (
    id uuid primary key default gen_random_uuid(),
    outing_id uuid not null references public.outings (id) on delete cascade,
    kind text not null check (kind in ('time', 'place', 'cancelled')),
    previous text not null default '',
    current text not null default '',
    created_at timestamptz not null default now()
);
create index outing_updates_outing_idx on public.outing_updates (outing_id, created_at desc);

-- Readable by moderators only (Apple App Review §1.2: report, with a timely
-- response). target_id is an outing, a person (user id) or a dog.
create table public.reports (
    id uuid primary key default gen_random_uuid(),
    reporter_id uuid not null references auth.users (id) on delete cascade,
    target_kind text not null check (target_kind in ('outing', 'profile', 'dog')),
    target_id uuid not null,
    reason text not null check (reason in ('danger', 'harassment', 'inappropriate', 'spam', 'other')),
    detail text not null default '' check (char_length(detail) <= 500),
    created_at timestamptz not null default now(),
    handled_at timestamptz,
    handled_by uuid references auth.users (id) on delete set null,
    outcome text check (outcome in ('removed', 'suspended', 'dismissed'))
);
create index reports_open_idx on public.reports (created_at) where handled_at is null;

-- A block takes effect at once, in both directions. Lifting it tombstones the
-- row; blocking again revives it.
create table public.blocks (
    blocker_id uuid not null references auth.users (id) on delete cascade,
    blocked_id uuid not null references auth.users (id) on delete cascade,
    created_at timestamptz not null default now(),
    lifted_at timestamptz,
    primary key (blocker_id, blocked_id),
    check (blocker_id <> blocked_id)
);
create index blocks_blocked_idx on public.blocks (blocked_id);

-- ---------------------------------------------------------------------------
-- Read helpers. SECURITY DEFINER so the views and policies can ask about rows
-- the caller may not read (a name, a count, a block made by someone else)
-- without exposing those rows. They live in the unexposed private schema and
-- answer for auth.uid(), or return a single value, never a row.
-- ---------------------------------------------------------------------------

-- The caller's zone if their profile is valid (exists, adult declaration,
-- not suspended); null otherwise. Every community read and write hangs on it.
create function private.community_zone()
returns text
language sql
stable
security definer
set search_path = ''
as $$
    select p.zone_id from public.community_profiles p
    where p.user_id = (select auth.uid())
      and p.suspended_at is null
      and p.adult_declared_at is not null;
$$;

create function private.community_zone_open(target_zone text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select coalesce((select z.is_open from public.community_zones z where z.id = target_zone), false);
$$;

-- A public name, as the person chose it. Used for the organizer of an
-- outing, the participants an organizer or an accepted person may see, and
-- the people one has blocked.
create function private.community_name(target_user uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
    select p.display_name from public.community_profiles p where p.user_id = target_user;
$$;

-- True when a live block exists between the caller and that person, whoever
-- made it. The blocked person cannot read the block itself.
create function private.community_blocked_with(other_user uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1 from public.blocks b
        where b.lifted_at is null
          and ((b.blocker_id = (select auth.uid()) and b.blocked_id = other_user)
            or (b.blocker_id = other_user and b.blocked_id = (select auth.uid())))
    );
$$;

create function private.community_is_moderator()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (select 1 from public.community_moderators m where m.user_id = (select auth.uid()));
$$;

-- Places taken: counts only, never who.
create function private.outing_humans_accepted(target_outing uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
    select count(*)::integer from public.outing_participants p
    where p.outing_id = target_outing and p.status = 'accepted';
$$;

create function private.outing_dogs_accepted(target_outing uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
    select count(*)::integer
    from public.outing_participants p
    join public.outing_dogs d on d.outing_id = p.outing_id and d.user_id = p.user_id
    where p.outing_id = target_outing and p.status = 'accepted' and d.retracted_at is null;
$$;

-- The caller's own request and attendance on an outing, or null.
create function private.outing_my_status(target_outing uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
    select p.status from public.outing_participants p
    where p.outing_id = target_outing and p.user_id = (select auth.uid());
$$;

create function private.outing_my_attended(target_outing uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select p.attended from public.outing_participants p
    where p.outing_id = target_outing and p.user_id = (select auth.uid());
$$;

-- Raises 'no profile' (P0001, so the client shows the profile screen rather
-- than "not allowed") and returns the caller's zone otherwise.
create function private.community_require_zone()
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    zone text := private.community_zone();
begin
    if zone is null then
        raise exception 'no profile';
    end if;
    return zone;
end;
$$;

revoke all on function private.community_zone() from public, anon;
revoke all on function private.community_zone_open(text) from public, anon;
revoke all on function private.community_name(uuid) from public, anon;
revoke all on function private.community_blocked_with(uuid) from public, anon;
revoke all on function private.community_is_moderator() from public, anon;
revoke all on function private.outing_humans_accepted(uuid) from public, anon;
revoke all on function private.outing_dogs_accepted(uuid) from public, anon;
revoke all on function private.outing_my_status(uuid) from public, anon;
revoke all on function private.outing_my_attended(uuid) from public, anon;
revoke all on function private.community_require_zone() from public, anon;
grant usage on schema private to authenticated;
grant execute on function private.community_zone() to authenticated;
grant execute on function private.community_zone_open(text) to authenticated;
grant execute on function private.community_name(uuid) to authenticated;
grant execute on function private.community_blocked_with(uuid) to authenticated;
grant execute on function private.community_is_moderator() to authenticated;
grant execute on function private.outing_humans_accepted(uuid) to authenticated;
grant execute on function private.outing_dogs_accepted(uuid) to authenticated;
grant execute on function private.outing_my_status(uuid) to authenticated;
grant execute on function private.outing_my_attended(uuid) to authenticated;
grant execute on function private.community_require_zone() to authenticated;

-- ---------------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------------

alter table public.community_zones enable row level security;
alter table public.community_profiles enable row level security;
alter table public.community_dogs enable row level security;
alter table public.community_moderators enable row level security;
alter table public.community_organizers enable row level security;
alter table public.outings enable row level security;
alter table public.outing_participants enable row level security;
alter table public.outing_dogs enable row level security;
alter table public.outing_updates enable row level security;
alter table public.reports enable row level security;
alter table public.blocks enable row level security;

-- Zones: anyone signed in sees the open ones, to choose one for a profile.
create policy "open zones are listed" on public.community_zones
for select to authenticated
using (is_open);

-- Profiles: each person reads their own row only, suspended or not, so the
-- app can tell a suspension apart from no profile. Others' names are only
-- given through the views and functions below. Writes go through save_profile.
create policy "a person reads their own profile" on public.community_profiles
for select to authenticated
using (user_id = (select auth.uid()));

-- Dogs: the owner reads, adds and edits their own; a valid profile is needed
-- to add one (an upsert checks the insert policy too). Retiring a dog is an
-- update of deleted_at, never a delete.
create policy "owners read their dogs" on public.community_dogs
for select to authenticated
using (owner_id = (select auth.uid()));

create policy "valid profiles add their own dogs" on public.community_dogs
for insert to authenticated
with check (owner_id = (select auth.uid()) and private.community_zone() is not null);

create policy "owners edit their dogs" on public.community_dogs
for update to authenticated
using (owner_id = (select auth.uid()))
with check (owner_id = (select auth.uid()));

-- Organizers: a person can tell whether they organize in a zone.
create policy "a person reads their own organizer rows" on public.community_organizers
for select to authenticated
using (user_id = (select auth.uid()));

-- Moderators: no policy, no privilege. Written by hand.

-- Outings, as ADR 0010 « Qui voit quoi »: a valid profile sees the published
-- outings of its open zone from yesterday on, unless a block stands between
-- it and the organizer; plus the outings it organizes or has a request in,
-- whatever their state (my_outings). No profile, no outing.
create policy "valid profiles see the outings of their zone and their own" on public.outings
for select to authenticated
using (
    private.community_zone() is not null
    and (
        organizer_id = (select auth.uid())
        or private.outing_my_status(id) is not null
        or (
            status = 'published'
            and zone_id = private.community_zone()
            and private.community_zone_open(zone_id)
            and starts_at >= now() - interval '1 day'
            and not private.community_blocked_with(organizer_id)
        )
    )
);

-- outing_participants, outing_dogs, outing_updates: no policy and no
-- privilege. Read through list_participants and list_outing_updates only.

-- Reports: moderators read them; filing goes through report().
create policy "moderators read reports" on public.reports
for select to authenticated
using (private.community_is_moderator());

-- Blocks: the blocker reads their own, so they can lift them. The blocked
-- person never learns about it from the server.
create policy "a person reads the blocks they made" on public.blocks
for select to authenticated
using (blocker_id = (select auth.uid()) and lifted_at is null);

-- ---------------------------------------------------------------------------
-- Views read by the client. security_invoker: the caller's RLS on outings and
-- blocks applies; names, counts and the caller's own state come from the
-- helpers above. Columns are OutingDTO's CodingKeys.
-- ---------------------------------------------------------------------------

create view public.visible_outings
with (security_invoker = true)
as
select
    o.id,
    o.organizer_id,
    coalesce(private.community_name(o.organizer_id), '') as organizer_name,
    o.zone_id,
    o.starts_at,
    o.duration_minutes,
    o.meeting_point,
    o.rules,
    o.human_capacity,
    o.dog_capacity,
    private.outing_humans_accepted(o.id) as humans_accepted,
    private.outing_dogs_accepted(o.id) as dogs_accepted,
    o.status,
    private.outing_my_status(o.id) as my_status,
    private.outing_my_attended(o.id) as my_attended
from public.outings o
where o.status = 'published'
  and o.zone_id = private.community_zone()
  and private.community_zone_open(o.zone_id)
  and o.starts_at >= now() - interval '1 day'
  and not private.community_blocked_with(o.organizer_id);

-- Outings the caller organizes or has a request in, any date, any state.
-- Like the reference server, a later block does not hide these: the person
-- keeps the trace of what they asked for or proposed.
create view public.my_outings
with (security_invoker = true)
as
select
    o.id,
    o.organizer_id,
    coalesce(private.community_name(o.organizer_id), '') as organizer_name,
    o.zone_id,
    o.starts_at,
    o.duration_minutes,
    o.meeting_point,
    o.rules,
    o.human_capacity,
    o.dog_capacity,
    private.outing_humans_accepted(o.id) as humans_accepted,
    private.outing_dogs_accepted(o.id) as dogs_accepted,
    o.status,
    private.outing_my_status(o.id) as my_status,
    private.outing_my_attended(o.id) as my_attended
from public.outings o
where private.community_zone() is not null
  and (o.organizer_id = (select auth.uid()) or private.outing_my_status(o.id) is not null);

-- The people the caller blocked, by the name they chose, so it can be undone.
create view public.my_blocks
with (security_invoker = true)
as
select b.blocked_id as user_id, private.community_name(b.blocked_id) as display_name
from public.blocks b
where b.blocker_id = (select auth.uid())
  and b.lifted_at is null
  and private.community_zone() is not null
  and private.community_name(b.blocked_id) is not null;

-- ---------------------------------------------------------------------------
-- Actions. Each private function is the rule, each public wrapper the
-- callable name with the client's parameter names (PostgREST matches them).
-- ---------------------------------------------------------------------------

-- Creates or updates the caller's profile. Refuses without the adult
-- declaration; stamps it the first time only.
create function private.save_profile(new_name text, new_zone text, adult boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    me uuid := (select auth.uid());
    clean text := btrim(coalesce(new_name, ''));
begin
    if me is null then
        raise exception 'not allowed: not signed in' using errcode = 'insufficient_privilege';
    end if;
    if adult is not true then
        raise exception 'not allowed: the pilot is for adults only' using errcode = 'insufficient_privilege';
    end if;
    if char_length(clean) not between 1 and 40 then
        raise exception 'a name of 1 to 40 characters' using errcode = 'check_violation';
    end if;
    if not private.community_zone_open(new_zone) then
        raise exception 'not allowed: this zone is not open' using errcode = 'insufficient_privilege';
    end if;
    if exists (select 1 from public.community_profiles p where p.user_id = me and p.suspended_at is not null) then
        raise exception 'no profile';
    end if;
    insert into public.community_profiles (user_id, display_name, zone_id, adult_declared_at)
    values (me, clean, new_zone, now())
    on conflict (user_id) do update
        set display_name = excluded.display_name, zone_id = excluded.zone_id;
end;
$$;

-- Ask to come, with some of one's own dogs. A pending or accepted request is
-- left as it is; a declined or withdrawn one starts again.
create function private.request_to_join(target_outing uuid, dog_list uuid[])
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    me uuid := (select auth.uid());
    zone text := private.community_require_zone();
    outing public.outings%rowtype;
    dogs uuid[];
    existing text;
begin
    select * into outing from public.outings o where o.id = target_outing;
    if not found
       or outing.status <> 'published'
       or outing.starts_at <= now()
       or outing.zone_id <> zone
       or not private.community_zone_open(outing.zone_id) then
        raise exception 'outing gone';
    end if;
    if private.community_blocked_with(outing.organizer_id) then
        raise exception 'blocked';
    end if;
    if outing.organizer_id = me then
        raise exception 'not allowed: the organizer does not ask' using errcode = 'insufficient_privilege';
    end if;
    select coalesce(array_agg(distinct d), '{}') into dogs from unnest(coalesce(dog_list, '{}')) d;
    if exists (
        select 1 from unnest(dogs) d
        where not exists (
            select 1 from public.community_dogs c
            where c.id = d and c.owner_id = me and c.deleted_at is null
        )
    ) then
        raise exception 'not allowed: only one''s own dogs' using errcode = 'insufficient_privilege';
    end if;

    select p.status into existing from public.outing_participants p
    where p.outing_id = target_outing and p.user_id = me
    for update;
    if existing in ('requested', 'accepted') then
        return;
    end if;

    insert into public.outing_participants (outing_id, user_id, status, requested_at)
    values (target_outing, me, 'requested', now())
    on conflict (outing_id, user_id) do update
        set status = 'requested', requested_at = now(), decided_at = null,
            attended = null, attended_declared_at = null;
    update public.outing_dogs d set retracted_at = now()
    where d.outing_id = target_outing and d.user_id = me and d.retracted_at is null;
    insert into public.outing_dogs (outing_id, user_id, dog_id)
    select target_outing, me, d from unnest(dogs) d
    on conflict (outing_id, user_id, dog_id) do update
        set retracted_at = null, announced_at = now();
end;
$$;

-- The organizer accepts or declines a pending request. The outing row is
-- locked first (SELECT ... FOR UPDATE), so two acceptances of the last place
-- run one after the other: the second waits for the lock, then counts again
-- under a new snapshot (READ COMMITTED) and is refused (C-REQ-06, C-AC-05).
-- People and dogs are two separate capacities.
create function private.decide_request(target_outing uuid, person uuid, accept boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    me uuid := (select auth.uid());
    zone text := private.community_require_zone();
    outing public.outings%rowtype;
    request public.outing_participants%rowtype;
    humans integer;
    dogs integer;
    their_dogs integer;
begin
    select * into outing from public.outings o where o.id = target_outing for update;
    if not found or outing.organizer_id <> me then
        raise exception 'not allowed: only the organizer decides' using errcode = 'insufficient_privilege';
    end if;
    if outing.status <> 'published' then
        raise exception 'outing gone';
    end if;
    select * into request from public.outing_participants p
    where p.outing_id = target_outing and p.user_id = person
    for update;
    if not found or request.status <> 'requested' then
        raise exception 'not allowed: no pending request' using errcode = 'insufficient_privilege';
    end if;
    if accept then
        humans := private.outing_humans_accepted(target_outing);
        dogs := private.outing_dogs_accepted(target_outing);
        select count(*)::integer into their_dogs from public.outing_dogs d
        where d.outing_id = target_outing and d.user_id = person and d.retracted_at is null;
        if humans + 1 > outing.human_capacity or dogs + their_dogs > outing.dog_capacity then
            raise exception 'outing full';
        end if;
    end if;
    update public.outing_participants p
    set status = case when accept then 'accepted' else 'declined' end, decided_at = now()
    where p.outing_id = target_outing and p.user_id = person;
end;
$$;

-- The participant steps back, whatever the state; an accepted place frees.
create function private.withdraw(target_outing uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    me uuid := (select auth.uid());
    zone text := private.community_require_zone();
begin
    update public.outing_participants p
    set status = 'withdrawn', decided_at = now()
    where p.outing_id = target_outing and p.user_id = me;
end;
$$;

-- Attendance is declared apart from the inscription, by an accepted person,
-- once the outing is over (PRD F10, C-AC-06).
create function private.declare_attendance(target_outing uuid, was_there boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    me uuid := (select auth.uid());
    zone text := private.community_require_zone();
begin
    if not exists (
        select 1 from public.outings o
        join public.outing_participants p on p.outing_id = o.id and p.user_id = me
        where o.id = target_outing
          and o.starts_at + make_interval(mins => o.duration_minutes) <= now()
          and p.status = 'accepted'
    ) or was_there is null then
        raise exception 'not allowed: only an accepted person, after the outing' using errcode = 'insufficient_privilege';
    end if;
    update public.outing_participants p
    set attended = was_there, attended_declared_at = now()
    where p.outing_id = target_outing and p.user_id = me;
end;
$$;

-- Only an organizer registered by hand in this zone, which must be theirs and
-- open, proposes an outing. The draft is checked again here (OutingDraft
-- checks it on the phone).
create function private.create_outing(
    target_zone text, start_time timestamptz, minutes integer, place text,
    outing_rules text, humans integer, dogs integer)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    me uuid := (select auth.uid());
    zone text := private.community_require_zone();
    new_id uuid;
begin
    if zone <> target_zone
       or not private.community_zone_open(target_zone)
       or not exists (
           select 1 from public.community_organizers g
           where g.user_id = me and g.zone_id = target_zone
       ) then
        raise exception 'not allowed: not an organizer of this zone' using errcode = 'insufficient_privilege';
    end if;
    if start_time is null or start_time <= now() then
        raise exception 'an outing starts in the future' using errcode = 'check_violation';
    end if;
    insert into public.outings (organizer_id, zone_id, starts_at, duration_minutes, meeting_point, rules,
                                human_capacity, dog_capacity)
    values (me, target_zone, start_time, minutes, btrim(place), btrim(coalesce(outing_rules, '')), humans, dogs)
    returning id into new_id;
    return new_id;
end;
$$;

-- The organizer moves the time or the place of a published outing. Each
-- change writes one outing_updates row the registered see.
create function private.update_outing(target_outing uuid, start_time timestamptz, place text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    me uuid := (select auth.uid());
    zone text := private.community_require_zone();
    outing public.outings%rowtype;
    clean text := btrim(coalesce(place, ''));
begin
    select * into outing from public.outings o where o.id = target_outing for update;
    if not found or outing.organizer_id <> me or outing.status <> 'published' then
        raise exception 'not allowed: only the organizer of a published outing' using errcode = 'insufficient_privilege';
    end if;
    if start_time is null then
        raise exception 'a time is needed' using errcode = 'check_violation';
    end if;
    -- Compared to the minute, as the editor sets it and as the update shows
    -- it: an unchanged time that came back through the phone with its
    -- sub-second part rounded is not a change to announce.
    if date_trunc('minute', start_time) <> date_trunc('minute', outing.starts_at) then
        insert into public.outing_updates (outing_id, kind, previous, current)
        values (target_outing, 'time',
                to_char(outing.starts_at at time zone 'Europe/Paris', 'DD/MM/YYYY HH24:MI'),
                to_char(start_time at time zone 'Europe/Paris', 'DD/MM/YYYY HH24:MI'));
    end if;
    if clean <> outing.meeting_point then
        insert into public.outing_updates (outing_id, kind, previous, current)
        values (target_outing, 'place', outing.meeting_point, clean);
    end if;
    update public.outings o
    set starts_at = start_time, meeting_point = clean, updated_at = now()
    where o.id = target_outing;
end;
$$;

create function private.cancel_outing(target_outing uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    me uuid := (select auth.uid());
    zone text := private.community_require_zone();
    outing public.outings%rowtype;
begin
    select * into outing from public.outings o where o.id = target_outing for update;
    if not found or outing.organizer_id <> me then
        raise exception 'not allowed: only the organizer cancels' using errcode = 'insufficient_privilege';
    end if;
    if outing.status <> 'published' then
        raise exception 'outing gone';
    end if;
    update public.outings o set status = 'cancelled', updated_at = now() where o.id = target_outing;
    insert into public.outing_updates (outing_id, kind) values (target_outing, 'cancelled');
end;
$$;

-- Who comes. The organizer sees every request with its attendance; an
-- accepted person sees the other accepted people and their announced dogs,
-- without attendance; anyone else is refused (C-REQ-01, C-AC-01).
create function private.list_participants(target_outing uuid)
returns table (user_id uuid, display_name text, status text, dog_names text[], attended boolean)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
    me uuid := (select auth.uid());
    zone text := private.community_require_zone();
    outing public.outings%rowtype;
    organizes boolean;
begin
    select * into outing from public.outings o where o.id = target_outing;
    if not found then
        raise exception 'outing gone';
    end if;
    organizes := outing.organizer_id = me;
    if not organizes and private.outing_my_status(target_outing) is distinct from 'accepted' then
        raise exception 'not allowed: participants are not public' using errcode = 'insufficient_privilege';
    end if;
    return query
    select p.user_id,
           pr.display_name,
           p.status,
           coalesce((
               select array_agg(c.name order by c.name)
               from public.outing_dogs d
               join public.community_dogs c on c.id = d.dog_id and c.deleted_at is null
               where d.outing_id = p.outing_id and d.user_id = p.user_id and d.retracted_at is null
           ), '{}'::text[]),
           case when organizes then p.attended end
    from public.outing_participants p
    join public.community_profiles pr on pr.user_id = p.user_id
    where p.outing_id = target_outing
      and (organizes or p.status = 'accepted')
    order by pr.display_name;
end;
$$;

-- Changes of time or place and cancellations, newest first, for the
-- organizer and the people with a pending or accepted request.
create function private.list_outing_updates(target_outing uuid)
returns setof public.outing_updates
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    me uuid := (select auth.uid());
    zone text := private.community_require_zone();
    outing public.outings%rowtype;
begin
    select * into outing from public.outings o where o.id = target_outing;
    if not found then
        raise exception 'outing gone';
    end if;
    if outing.organizer_id <> me
       and coalesce(private.outing_my_status(target_outing), '') not in ('requested', 'accepted') then
        raise exception 'not allowed: updates go to the registered' using errcode = 'insufficient_privilege';
    end if;
    return query
    select u.* from public.outing_updates u
    where u.outing_id = target_outing
    order by u.created_at desc, u.kind;
end;
$$;

create function private.report(kind text, target uuid, why text, words text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    me uuid := (select auth.uid());
    zone text := private.community_require_zone();
begin
    insert into public.reports (reporter_id, target_kind, target_id, reason, detail)
    values (me, kind, target, why, btrim(coalesce(words, '')));
end;
$$;

create function private.block(person uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    me uuid := (select auth.uid());
    zone text := private.community_require_zone();
begin
    if person is null or person = me
       or not exists (select 1 from public.community_profiles p where p.user_id = person) then
        raise exception 'not allowed: nobody to block' using errcode = 'insufficient_privilege';
    end if;
    insert into public.blocks (blocker_id, blocked_id)
    values (me, person)
    on conflict (blocker_id, blocked_id) do update set created_at = now(), lifted_at = null;
end;
$$;

-- Lifts only a block the caller made; lifting nothing is not an error.
create function private.unblock(person uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    me uuid := (select auth.uid());
    zone text := private.community_require_zone();
begin
    update public.blocks b set lifted_at = now()
    where b.blocker_id = me and b.blocked_id = person and b.lifted_at is null;
end;
$$;

revoke all on function private.save_profile(text, text, boolean) from public, anon;
revoke all on function private.request_to_join(uuid, uuid[]) from public, anon;
revoke all on function private.decide_request(uuid, uuid, boolean) from public, anon;
revoke all on function private.withdraw(uuid) from public, anon;
revoke all on function private.declare_attendance(uuid, boolean) from public, anon;
revoke all on function private.create_outing(text, timestamptz, integer, text, text, integer, integer) from public, anon;
revoke all on function private.update_outing(uuid, timestamptz, text) from public, anon;
revoke all on function private.cancel_outing(uuid) from public, anon;
revoke all on function private.list_participants(uuid) from public, anon;
revoke all on function private.list_outing_updates(uuid) from public, anon;
revoke all on function private.report(text, uuid, text, text) from public, anon;
revoke all on function private.block(uuid) from public, anon;
revoke all on function private.unblock(uuid) from public, anon;
grant execute on function private.save_profile(text, text, boolean) to authenticated;
grant execute on function private.request_to_join(uuid, uuid[]) to authenticated;
grant execute on function private.decide_request(uuid, uuid, boolean) to authenticated;
grant execute on function private.withdraw(uuid) to authenticated;
grant execute on function private.declare_attendance(uuid, boolean) to authenticated;
grant execute on function private.create_outing(text, timestamptz, integer, text, text, integer, integer) to authenticated;
grant execute on function private.update_outing(uuid, timestamptz, text) to authenticated;
grant execute on function private.cancel_outing(uuid) to authenticated;
grant execute on function private.list_participants(uuid) to authenticated;
grant execute on function private.list_outing_updates(uuid) to authenticated;
grant execute on function private.report(text, uuid, text, text) to authenticated;
grant execute on function private.block(uuid) to authenticated;
grant execute on function private.unblock(uuid) to authenticated;

-- Public wrappers: the names and parameter names the client sends.

create function public.save_profile(display_name text, zone_id text, adult_declared boolean)
returns void language sql security invoker set search_path = ''
as $$ select private.save_profile(display_name, zone_id, adult_declared); $$;

create function public.request_to_join(outing_id uuid, dog_ids uuid[])
returns void language sql security invoker set search_path = ''
as $$ select private.request_to_join(outing_id, dog_ids); $$;

create function public.decide_request(outing_id uuid, user_id uuid, accept boolean)
returns void language sql security invoker set search_path = ''
as $$ select private.decide_request(outing_id, user_id, accept); $$;

create function public.withdraw(outing_id uuid)
returns void language sql security invoker set search_path = ''
as $$ select private.withdraw(outing_id); $$;

create function public.declare_attendance(outing_id uuid, attended boolean)
returns void language sql security invoker set search_path = ''
as $$ select private.declare_attendance(outing_id, attended); $$;

create function public.create_outing(
    zone_id text, starts_at timestamptz, duration_minutes integer, meeting_point text,
    rules text, human_capacity integer, dog_capacity integer)
returns uuid language sql security invoker set search_path = ''
as $$
    select private.create_outing(zone_id, starts_at, duration_minutes, meeting_point,
                                 rules, human_capacity, dog_capacity);
$$;

create function public.update_outing(outing_id uuid, starts_at timestamptz, meeting_point text)
returns void language sql security invoker set search_path = ''
as $$ select private.update_outing(outing_id, starts_at, meeting_point); $$;

create function public.cancel_outing(outing_id uuid)
returns void language sql security invoker set search_path = ''
as $$ select private.cancel_outing(outing_id); $$;

create function public.list_participants(outing_id uuid)
returns table (user_id uuid, display_name text, status text, dog_names text[], attended boolean)
language sql stable security invoker set search_path = ''
as $$ select * from private.list_participants(outing_id); $$;

-- setof the table type, not RETURNS TABLE: its outing_id column would clash
-- with the outing_id parameter the client sends.
create function public.list_outing_updates(outing_id uuid)
returns setof public.outing_updates
language sql stable security invoker set search_path = ''
as $$ select * from private.list_outing_updates(outing_id); $$;

create function public.report(target_kind text, target_id uuid, reason text, detail text)
returns void language sql security invoker set search_path = ''
as $$ select private.report(target_kind, target_id, reason, detail); $$;

create function public.block(user_id uuid)
returns void language sql security invoker set search_path = ''
as $$ select private.block(user_id); $$;

create function public.unblock(user_id uuid)
returns void language sql security invoker set search_path = ''
as $$ select private.unblock(user_id); $$;

-- Supabase's default privileges give EXECUTE on new public functions to anon
-- directly, not only through PUBLIC: revoke from each, then grant.
revoke all on function public.save_profile(text, text, boolean) from public, anon, authenticated;
revoke all on function public.request_to_join(uuid, uuid[]) from public, anon, authenticated;
revoke all on function public.decide_request(uuid, uuid, boolean) from public, anon, authenticated;
revoke all on function public.withdraw(uuid) from public, anon, authenticated;
revoke all on function public.declare_attendance(uuid, boolean) from public, anon, authenticated;
revoke all on function public.create_outing(text, timestamptz, integer, text, text, integer, integer) from public, anon, authenticated;
revoke all on function public.update_outing(uuid, timestamptz, text) from public, anon, authenticated;
revoke all on function public.cancel_outing(uuid) from public, anon, authenticated;
revoke all on function public.list_participants(uuid) from public, anon, authenticated;
revoke all on function public.list_outing_updates(uuid) from public, anon, authenticated;
revoke all on function public.report(text, uuid, text, text) from public, anon, authenticated;
revoke all on function public.block(uuid) from public, anon, authenticated;
revoke all on function public.unblock(uuid) from public, anon, authenticated;
grant execute on function public.save_profile(text, text, boolean) to authenticated;
grant execute on function public.request_to_join(uuid, uuid[]) to authenticated;
grant execute on function public.decide_request(uuid, uuid, boolean) to authenticated;
grant execute on function public.withdraw(uuid) to authenticated;
grant execute on function public.declare_attendance(uuid, boolean) to authenticated;
grant execute on function public.create_outing(text, timestamptz, integer, text, text, integer, integer) to authenticated;
grant execute on function public.update_outing(uuid, timestamptz, text) to authenticated;
grant execute on function public.cancel_outing(uuid) to authenticated;
grant execute on function public.list_participants(uuid) to authenticated;
grant execute on function public.list_outing_updates(uuid) to authenticated;
grant execute on function public.report(text, uuid, text, text) to authenticated;
grant execute on function public.block(uuid) to authenticated;
grant execute on function public.unblock(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Data API exposure, as 20261006191346_tighten_grants.sql: start from
-- nothing, then grant exactly what the policies expect. Nothing for anon.
-- No DELETE anywhere: dogs, blocks and announced dogs are tombstoned.
-- ---------------------------------------------------------------------------

revoke all on public.community_zones, public.community_profiles, public.community_dogs,
    public.community_moderators, public.community_organizers, public.outings,
    public.outing_participants, public.outing_dogs, public.outing_updates,
    public.reports, public.blocks,
    public.visible_outings, public.my_outings, public.my_blocks
    from authenticated, anon;

grant select on public.community_zones to authenticated;
grant select on public.community_profiles to authenticated;
grant select, insert, update on public.community_dogs to authenticated;
grant select on public.community_organizers to authenticated;
grant select on public.outings to authenticated;
grant select on public.reports to authenticated;
grant select on public.blocks to authenticated;
grant select on public.visible_outings, public.my_outings, public.my_blocks to authenticated;
