-- Nearby dogs of the foyer, on agreement (decision of Guillaume, 2026-10-08).
--
-- A member who turns it on shares, during their own balade only, where they
-- are with the other members of their household, so a member walking close by
-- is told "Un chien de votre foyer est à ~ 30 m". Never with anyone outside
-- the household, never a track, never a history:
--   * one row per member and household, overwritten at each fix;
--   * coordinates rounded by the server to 4 decimals (about 10 m), whatever
--     the phone sends;
--   * a row expires two minutes after its last write and is invisible after;
--   * the member deletes it when the balade ends or the setting is turned off.
-- Not published to Realtime: the phones ask every few seconds while walking.

create table public.live_positions (
    household_id uuid not null,
    user_id uuid not null default auth.uid(),
    latitude double precision not null check (latitude between -90 and 90),
    longitude double precision not null check (longitude between -180 and 180),
    updated_at timestamptz not null default now(),
    expires_at timestamptz not null default now() + interval '2 minutes',
    primary key (household_id, user_id),
    -- Leaving the household takes the position with the membership.
    foreign key (household_id, user_id)
        references public.household_members (household_id, user_id) on delete cascade
);

-- The server, not the phone, decides the precision and the lifetime.
create function private.live_position_rules()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    new.latitude := round(new.latitude::numeric, 4)::double precision;
    new.longitude := round(new.longitude::numeric, 4)::double precision;
    new.updated_at := now();
    new.expires_at := now() + interval '2 minutes';
    return new;
end;
$$;

create trigger live_positions_rules
before insert or update on public.live_positions
for each row execute function private.live_position_rules();

alter table public.live_positions enable row level security;

create policy "members read the live positions of their household" on public.live_positions
for select to authenticated
using (
    -- Their own row, even expired, so they can still delete it (a delete
    -- only reaches the rows the read policy shows).
    user_id = (select auth.uid())
    or (expires_at > now()
        and private.has_role(household_id, array['owner', 'contributor', 'reader']))
);

create policy "a member shares their own position" on public.live_positions
for insert to authenticated
with check (
    user_id = (select auth.uid())
    and private.has_role(household_id, array['owner', 'contributor', 'reader'])
);

create policy "a member moves their own position" on public.live_positions
for update to authenticated
using (user_id = (select auth.uid()))
with check (
    user_id = (select auth.uid())
    and private.has_role(household_id, array['owner', 'contributor', 'reader'])
);

create policy "a member stops sharing" on public.live_positions
for delete to authenticated
using (user_id = (select auth.uid()));

revoke all on public.live_positions from authenticated, anon;
grant select, insert, update, delete on public.live_positions to authenticated;
