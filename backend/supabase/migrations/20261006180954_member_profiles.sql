-- How members of a household name themselves to each other (PRD F08).
--
-- Auth knows an Apple identity, not a name another member would recognise,
-- and Apple only hands the name over once. So each member picks the name the
-- household sees, per household, and only they can change it.
--
-- The row belongs to the membership: removing a member removes their name.

create table public.member_profiles (
    household_id uuid not null,
    user_id uuid not null,
    display_name text not null check (char_length(btrim(display_name)) between 1 and 40),
    updated_at timestamptz not null default now(),
    primary key (household_id, user_id),
    foreign key (household_id, user_id)
        references public.household_members (household_id, user_id) on delete cascade
);

alter table public.member_profiles enable row level security;

create policy "members read the names of their household" on public.member_profiles
for select to authenticated
using (private.has_role(household_id, array['owner', 'contributor', 'reader']));

create policy "a member names themselves" on public.member_profiles
for insert to authenticated
with check (
    user_id = (select auth.uid())
    and private.has_role(household_id, array['owner', 'contributor', 'reader'])
);

create policy "a member renames themselves" on public.member_profiles
for update to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

grant select, insert, update on public.member_profiles to authenticated;
revoke all on public.member_profiles from anon;
