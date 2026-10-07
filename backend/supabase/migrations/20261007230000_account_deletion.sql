-- Account deletion (App Store guideline 5.1.1(v)), separate from the household
-- details because it deletes rows: tools/backend/apply-migration.sh refuses any
-- migration containing a delete, so this one is applied by hand, after reading.

-- dog_update_rules again, with one exception: during an account deletion the
-- rows are handed over to someone else, so the caller's stamp would undo it.
create or replace function private.dog_update_rules()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    if new.household_id <> old.household_id then
        raise exception 'a dog keeps its household' using errcode = 'check_violation';
    end if;
    if coalesce(current_setting('trufflo.handing_over', true), '') <> 'on' then
        new.updated_by := (select auth.uid());
    end if;
    new.updated_at := now();
    return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Account deletion (App Store guideline 5.1.1(v)): the signed-in person
-- deletes their own account and everything the server holds for them.
--
-- A household they alone own goes with them when nobody else is in it. If
-- other members remain and none of them is an owner, deletion is refused:
-- the person names another owner first (the same rule as leaving).
-- ---------------------------------------------------------------------------

create function private.delete_my_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    me uuid := (select auth.uid());
    held record;
begin
    if me is null then
        raise exception 'not signed in' using errcode = 'insufficient_privilege';
    end if;
    for held in
        select m.household_id from public.household_members m
        where m.user_id = me and m.role = 'owner'
    loop
        if not exists (select 1 from public.household_members o
                       where o.household_id = held.household_id and o.user_id <> me) then
            delete from public.households where id = held.household_id;
        elsif not exists (select 1 from public.household_members o
                          where o.household_id = held.household_id and o.user_id <> me
                            and o.role = 'owner') then
            raise exception 'name another owner first' using errcode = 'check_violation';
        end if;
    end loop;
    -- `households.created_by` and `dogs.updated_by` cascade from auth.users:
    -- left as they are, deleting this account would delete a household the
    -- others still use, and its dogs. Hand them to a remaining owner, or to
    -- a remaining member for the dogs, first.
    update public.households h
    set created_by = (select o.user_id from public.household_members o
                      where o.household_id = h.id and o.user_id <> me and o.role = 'owner'
                      order by o.joined_at limit 1)
    where h.created_by = me
      and exists (select 1 from public.household_members o
                  where o.household_id = h.id and o.user_id <> me and o.role = 'owner');
    -- The dogs trigger stamps updated_by with the caller; this flag, local to
    -- the transaction, lets the hand-over through (see dog_update_rules).
    perform set_config('trufflo.handing_over', 'on', true);
    update public.dogs d
    set updated_by = (select o.user_id from public.household_members o
                      where o.household_id = d.household_id and o.user_id <> me
                      order by (o.role = 'owner') desc, o.joined_at limit 1)
    where d.updated_by = me
      and exists (select 1 from public.household_members o
                  where o.household_id = d.household_id and o.user_id <> me);
    perform set_config('trufflo.handing_over', 'off', true);
    -- Memberships, own walks, plans and invites cascade from auth.users.
    delete from auth.users where id = me;
end;
$$;
revoke all on function private.delete_my_account() from public;
grant execute on function private.delete_my_account() to authenticated;

create function public.delete_my_account()
returns void
language sql
security invoker
set search_path = ''
as $$
    select private.delete_my_account();
$$;
revoke all on function public.delete_my_account() from public;
grant execute on function public.delete_my_account() to authenticated;
