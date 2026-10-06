-- M2, PRD F08: a household shares walk SUMMARIES between its members.
--
-- What is deliberately absent (DATA-CONTRACTS §5, ADR-007):
--   * no coordinates, no track, no route file: precise routes stay on the phone;
--   * no private note, no dog photo, no preferences note;
--   * no service-role key in the app: every read and write is a member acting
--     under row level security, and the server is the authority on rights.
--
-- Roles: owner ("responsable"), contributor, reader. A contributor corrects
-- their own walks, not someone else's; an owner may correct any walk of the
-- household. Removing a member stops their server reads at once.
--
-- Deletions are tombstones (deleted_at) so a deleted item does not come back
-- through a later sync (DATA-CONTRACTS §8).

create schema if not exists private;

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table public.households (
    id uuid primary key default gen_random_uuid(),
    name text not null check (char_length(name) between 1 and 80),
    created_by uuid not null default auth.uid() references auth.users (id) on delete cascade,
    created_at timestamptz not null default now()
);

create table public.household_members (
    household_id uuid not null references public.households (id) on delete cascade,
    user_id uuid not null references auth.users (id) on delete cascade,
    role text not null check (role in ('owner', 'contributor', 'reader')),
    joined_at timestamptz not null default now(),
    primary key (household_id, user_id)
);
create index household_members_user_idx on public.household_members (user_id);

create table public.household_invites (
    id uuid primary key default gen_random_uuid(),
    household_id uuid not null references public.households (id) on delete cascade,
    -- 122 random bits, shared out of band (link, message). Single use.
    token text not null unique default replace(gen_random_uuid()::text, '-', ''),
    role text not null check (role in ('contributor', 'reader')),
    created_by uuid not null default auth.uid() references auth.users (id) on delete cascade,
    created_at timestamptz not null default now(),
    expires_at timestamptz not null default now() + interval '7 days',
    accepted_by uuid references auth.users (id) on delete set null,
    accepted_at timestamptz,
    revoked_at timestamptz
);
create index household_invites_household_idx on public.household_invites (household_id);

create table public.dogs (
    -- The client's stable UUID, never a local persistence identifier.
    id uuid primary key,
    household_id uuid not null references public.households (id) on delete cascade,
    name text not null check (char_length(name) between 1 and 80),
    breed_kind text not null check (breed_kind in ('known', 'mixed', 'unknown')),
    breed_label text not null default '' check (char_length(breed_label) <= 80),
    age_description text not null default '' check (char_length(age_description) <= 50),
    updated_by uuid not null default auth.uid() references auth.users (id) on delete cascade,
    updated_at timestamptz not null default now(),
    deleted_at timestamptz
);
create index dogs_household_idx on public.dogs (household_id);

create table public.walks (
    id uuid primary key,
    household_id uuid not null references public.households (id) on delete cascade,
    author_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
    revision integer not null default 1 check (revision >= 1),
    source text not null check (source in ('manual', 'gps')),
    quality text not null check (quality in ('gpsRecorded', 'gpsPartial', 'manual', 'unavailable')),
    started_at timestamptz not null,
    ended_at timestamptz not null,
    confirmed_seconds double precision not null check (confirmed_seconds > 0 and confirmed_seconds <= 86400),
    -- Null means "not measured", never zero (W004).
    recorded_path_meters double precision check (recorded_path_meters >= 0),
    corrected_at timestamptz,
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    check (ended_at >= started_at),
    -- A declared walk never carries a distance.
    check (source = 'gps' or recorded_path_meters is null)
);
create index walks_household_ended_idx on public.walks (household_id, ended_at desc);
create index walks_author_idx on public.walks (author_id);

create table public.walk_dogs (
    walk_id uuid not null references public.walks (id) on delete cascade,
    dog_id uuid not null references public.dogs (id) on delete cascade,
    dog_name_snapshot text not null check (char_length(dog_name_snapshot) between 1 and 80),
    primary key (walk_id, dog_id)
);
create index walk_dogs_dog_idx on public.walk_dogs (dog_id);

-- ---------------------------------------------------------------------------
-- Membership helpers. SECURITY DEFINER so policies on household_members can
-- ask "is this user a member" without recursing into their own policy. They
-- live in the unexposed private schema and only ever answer for auth.uid().
-- ---------------------------------------------------------------------------

create function private.has_role(target_household uuid, roles text[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1 from public.household_members m
        where m.household_id = target_household
          and m.user_id = (select auth.uid())
          and m.role = any (roles)
    );
$$;

create function private.can_write_walk(target_walk uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1 from public.walks w
        where w.id = target_walk
          and (
              (w.author_id = (select auth.uid())
               and private.has_role(w.household_id, array['owner', 'contributor']))
              or private.has_role(w.household_id, array['owner'])
          )
    );
$$;

revoke all on function private.has_role(uuid, text[]) from public;
revoke all on function private.can_write_walk(uuid) from public;
grant usage on schema private to authenticated;
grant execute on function private.has_role(uuid, text[]) to authenticated;
grant execute on function private.can_write_walk(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------

-- The creator of a household becomes its owner, in the same transaction.
create function private.add_creator_as_owner()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    insert into public.household_members (household_id, user_id, role)
    values (new.id, new.created_by, 'owner');
    return new;
end;
$$;
revoke all on function private.add_creator_as_owner() from public;

create trigger households_add_owner
after insert on public.households
for each row execute function private.add_creator_as_owner();

-- A household always keeps at least one owner: the last owner can neither
-- leave nor be demoted. Deleting the household is the way out.
create function private.keep_an_owner()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if old.role = 'owner'
       and (tg_op = 'DELETE' or new.role <> 'owner')
       and exists (select 1 from public.households h where h.id = old.household_id)
       and not exists (
           select 1 from public.household_members m
           where m.household_id = old.household_id
             and m.role = 'owner'
             and m.user_id <> old.user_id
       ) then
        raise exception 'a household keeps at least one owner'
            using errcode = 'check_violation';
    end if;
    return coalesce(new, old);
end;
$$;
revoke all on function private.keep_an_owner() from public;

create trigger household_members_keep_owner
before update or delete on public.household_members
for each row execute function private.keep_an_owner();

-- On a walk update: author and household are fixed, the revision moves
-- forward by one, and the server stamps the time.
create function private.walk_update_rules()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    if new.author_id <> old.author_id or new.household_id <> old.household_id then
        raise exception 'a walk keeps its author and household'
            using errcode = 'check_violation';
    end if;
    new.revision := old.revision + 1;
    new.updated_at := now();
    return new;
end;
$$;

create trigger walks_update_rules
before update on public.walks
for each row execute function private.walk_update_rules();

create function private.dog_update_rules()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    if new.household_id <> old.household_id then
        raise exception 'a dog keeps its household' using errcode = 'check_violation';
    end if;
    new.updated_by := (select auth.uid());
    new.updated_at := now();
    return new;
end;
$$;

create trigger dogs_update_rules
before update on public.dogs
for each row execute function private.dog_update_rules();

-- ---------------------------------------------------------------------------
-- Accepting an invite. The joining user is not a member yet, so they cannot
-- read the invite under RLS: the check runs in a definer function that only
-- ever acts for auth.uid(), and only through a valid, unused, unexpired token.
-- ---------------------------------------------------------------------------

create function private.accept_household_invite(invite_token text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    invite public.household_invites%rowtype;
    me uuid := (select auth.uid());
begin
    if me is null then
        raise exception 'not signed in' using errcode = 'insufficient_privilege';
    end if;
    select * into invite from public.household_invites
    where token = invite_token
    for update;
    if not found
       or invite.revoked_at is not null
       or invite.accepted_at is not null
       or invite.expires_at < now() then
        raise exception 'invite not valid' using errcode = 'invalid_parameter_value';
    end if;
    insert into public.household_members (household_id, user_id, role)
    values (invite.household_id, me, invite.role)
    on conflict (household_id, user_id) do nothing;
    update public.household_invites
    set accepted_by = me, accepted_at = now()
    where id = invite.id;
    return invite.household_id;
end;
$$;
revoke all on function private.accept_household_invite(text) from public;
grant execute on function private.accept_household_invite(text) to authenticated;

-- The callable entry point exposed to the Data API: an invoker wrapper, so
-- the privileged code stays out of the exposed schema.
create function public.accept_household_invite(invite_token text)
returns uuid
language sql
security invoker
set search_path = ''
as $$
    select private.accept_household_invite(invite_token);
$$;
revoke all on function public.accept_household_invite(text) from public;
grant execute on function public.accept_household_invite(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------------

alter table public.households enable row level security;
alter table public.household_members enable row level security;
alter table public.household_invites enable row level security;
alter table public.dogs enable row level security;
alter table public.walks enable row level security;
alter table public.walk_dogs enable row level security;

-- Households
create policy "members read their household" on public.households
for select to authenticated
using (private.has_role(id, array['owner', 'contributor', 'reader']));

create policy "anyone signed in creates a household they own" on public.households
for insert to authenticated
with check (created_by = (select auth.uid()));

create policy "owners rename" on public.households
for update to authenticated
using (private.has_role(id, array['owner']))
with check (private.has_role(id, array['owner']));

create policy "owners delete" on public.households
for delete to authenticated
using (private.has_role(id, array['owner']));

-- Members
create policy "members see who is in the household" on public.household_members
for select to authenticated
using (private.has_role(household_id, array['owner', 'contributor', 'reader']));

create policy "owners change roles" on public.household_members
for update to authenticated
using (private.has_role(household_id, array['owner']))
with check (private.has_role(household_id, array['owner']));

create policy "owners remove members, anyone leaves" on public.household_members
for delete to authenticated
using (
    user_id = (select auth.uid())
    or private.has_role(household_id, array['owner'])
);

-- Invites: owners only. Acceptance goes through accept_household_invite.
create policy "owners read invites" on public.household_invites
for select to authenticated
using (private.has_role(household_id, array['owner']));

create policy "owners create invites" on public.household_invites
for insert to authenticated
with check (
    created_by = (select auth.uid())
    and private.has_role(household_id, array['owner'])
);

create policy "owners revoke invites" on public.household_invites
for update to authenticated
using (private.has_role(household_id, array['owner']))
with check (private.has_role(household_id, array['owner']));

-- Dogs
create policy "members read dogs" on public.dogs
for select to authenticated
using (private.has_role(household_id, array['owner', 'contributor', 'reader']));

create policy "writers add dogs" on public.dogs
for insert to authenticated
with check (private.has_role(household_id, array['owner', 'contributor']));

create policy "writers edit dogs" on public.dogs
for update to authenticated
using (private.has_role(household_id, array['owner', 'contributor']))
with check (private.has_role(household_id, array['owner', 'contributor']));

-- Walks
create policy "members read walks" on public.walks
for select to authenticated
using (private.has_role(household_id, array['owner', 'contributor', 'reader']));

create policy "writers add their own walks" on public.walks
for insert to authenticated
with check (
    author_id = (select auth.uid())
    and private.has_role(household_id, array['owner', 'contributor'])
);

create policy "authors and owners correct walks" on public.walks
for update to authenticated
using (
    (author_id = (select auth.uid()) and private.has_role(household_id, array['owner', 'contributor']))
    or private.has_role(household_id, array['owner'])
)
with check (
    (author_id = (select auth.uid()) and private.has_role(household_id, array['owner', 'contributor']))
    or private.has_role(household_id, array['owner'])
);

-- Walk participants follow the walk's write rights.
create policy "members read participants" on public.walk_dogs
for select to authenticated
using (exists (
    select 1 from public.walks w
    where w.id = walk_id
      and private.has_role(w.household_id, array['owner', 'contributor', 'reader'])
));

create policy "walk writers add participants" on public.walk_dogs
for insert to authenticated
with check (
    private.can_write_walk(walk_id)
    and exists (
        select 1 from public.walks w join public.dogs d on d.household_id = w.household_id
        where w.id = walk_id and d.id = dog_id
    )
);

create policy "walk writers remove participants" on public.walk_dogs
for delete to authenticated
using (private.can_write_walk(walk_id));

-- ---------------------------------------------------------------------------
-- Data API exposure: explicit, since new tables are no longer exposed by
-- default. Only signed-in users; nothing for anon. Rows are then filtered by
-- the policies above. No DELETE on dogs and walks: they are tombstoned.
-- ---------------------------------------------------------------------------

revoke all on public.households, public.household_members, public.household_invites,
    public.dogs, public.walks, public.walk_dogs from anon;

grant select, insert, update, delete on public.households to authenticated;
grant select, update, delete on public.household_members to authenticated;
grant select, insert, update on public.household_invites to authenticated;
grant select, insert, update on public.dogs to authenticated;
grant select, insert, update on public.walks to authenticated;
grant select, insert, delete on public.walk_dogs to authenticated;
