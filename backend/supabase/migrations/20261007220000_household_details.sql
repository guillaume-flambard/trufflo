-- Chantier 8 (2026-10-07): what the household shares beyond the bare walk
-- summary, and the daily tip served from the database. Account deletion is
-- in the next migration: it deletes rows, so it is applied by hand.
--
-- Still deliberately absent (DATA-CONTRACTS §5, ADR-007): coordinates,
-- tracks, route files, the place a walk went, the private note, dog and walk
-- photos, the dog's sex, preferences. A planned walk carries the name of the
-- place it is planned for, never coordinates: that is what the plan shares.

-- ---------------------------------------------------------------------------
-- Walks: title, mood and weather, as the person wrote or the phone measured
-- them. All optional; an old client simply leaves them empty. The place a walk
-- went stays on the iPhone, like its track (HouseholdSyncTests).
-- ---------------------------------------------------------------------------

alter table public.walks
    add column title text not null default '' check (char_length(title) <= 80),
    add column mood text check (mood in ('great', 'calm', 'discovery', 'tough')),
    add column weather text check (weather in ('sunny', 'cloudy', 'rainy', 'snowy', 'windy', 'foggy')),
    add column temperature_c double precision check (temperature_c between -60 and 60);

-- ---------------------------------------------------------------------------
-- Dogs: size, weight and traits, as the person declared them. Never inferred
-- from the walks (rule 3). Sex, photo and preferences stay on the iPhone.
-- ---------------------------------------------------------------------------

alter table public.dogs
    add column size text check (size in ('small', 'medium', 'large')),
    add column weight_kg double precision check (weight_kg > 0 and weight_kg <= 120),
    add column traits text[] not null default '{}'
        check (traits <@ array['sociable', 'calm', 'energetic', 'fearful', 'playful', 'other']::text[]);

-- ---------------------------------------------------------------------------
-- Planned walks ("Prochaine balade"): the household sees who plans to go out,
-- when, and where by name. Tombstoned like walks so Realtime can check rights.
-- ---------------------------------------------------------------------------

create table public.planned_walks (
    -- The client's stable UUID.
    id uuid primary key,
    household_id uuid not null references public.households (id) on delete cascade,
    author_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
    planned_at timestamptz not null,
    place_name text not null default '' check (char_length(place_name) <= 120),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz
);
create index planned_walks_household_idx on public.planned_walks (household_id, planned_at);

create function private.planned_walk_update_rules()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    if new.author_id <> old.author_id or new.household_id <> old.household_id then
        raise exception 'a planned walk keeps its author and household'
            using errcode = 'check_violation';
    end if;
    new.updated_at := now();
    return new;
end;
$$;

create trigger planned_walks_update_rules
before update on public.planned_walks
for each row execute function private.planned_walk_update_rules();

alter table public.planned_walks enable row level security;

create policy "members read planned walks" on public.planned_walks
for select to authenticated
using (private.has_role(household_id, array['owner', 'contributor', 'reader']));

create policy "writers plan their own walks" on public.planned_walks
for insert to authenticated
with check (
    author_id = (select auth.uid())
    and private.has_role(household_id, array['owner', 'contributor'])
);

create policy "authors and owners change plans" on public.planned_walks
for update to authenticated
using (
    (author_id = (select auth.uid()) and private.has_role(household_id, array['owner', 'contributor']))
    or private.has_role(household_id, array['owner'])
)
with check (
    (author_id = (select auth.uid()) and private.has_role(household_id, array['owner', 'contributor']))
    or private.has_role(household_id, array['owner'])
);

revoke all on public.planned_walks from authenticated, anon;
grant select, insert, update on public.planned_walks to authenticated;

alter publication supabase_realtime add table public.planned_walks;

-- ---------------------------------------------------------------------------
-- Daily tips ("Conseil du jour"): editorial content, the same for everyone,
-- about the outing and never about a dog. The one table anon may read: the
-- journal works without an account, and nothing here is personal.
-- ---------------------------------------------------------------------------

create table public.daily_tips (
    id integer generated always as identity primary key,
    title text not null check (char_length(title) between 1 and 60),
    body text not null check (char_length(body) between 1 and 120),
    position integer not null unique,
    active boolean not null default true
);

alter table public.daily_tips enable row level security;

create policy "everyone reads active tips" on public.daily_tips
for select to anon, authenticated
using (active);

revoke all on public.daily_tips from authenticated, anon;
grant select on public.daily_tips to authenticated, anon;

insert into public.daily_tips (position, title, body) values
    (1, 'Un nouveau coin à explorer ?', 'Changer de rue, c''est de nouvelles odeurs.'),
    (2, 'Pensez à l''eau.', 'Une gourde et un bol pliable suffisent.'),
    (3, 'Prenez votre temps.', 'Renifler fait aussi partie de la balade.'),
    (4, 'Le soir tombe tôt.', 'Une veste claire aide à être vus.'),
    (5, 'Un sac de plus.', 'Glissez-en un de rechange dans la laisse.'),
    (6, 'Des pattes propres.', 'Un coup d''œil aux coussinets au retour.'),
    (7, 'À plusieurs ?', 'Le foyer partagé dit qui est déjà sorti.');
