-- Grants were added on top of Supabase's default privileges instead of
-- replacing them: `authenticated` still held DELETE, TRUNCATE, REFERENCES
-- and TRIGGER on every household table (found by realtime_test.sql on
-- 2026-10-06, same state in production). TRUNCATE ignores row level
-- security. PostgREST does not expose it, but nothing here should rest on
-- that. Start from nothing, then grant exactly what the policies expect.
--
-- Any table added later must repeat this pattern: revoke all, then grant.

revoke all on public.households, public.household_members, public.household_invites,
    public.dogs, public.walks, public.walk_dogs, public.member_profiles
    from authenticated, anon;

grant select, insert, update, delete on public.households to authenticated;
grant select, update, delete on public.household_members to authenticated;
grant select, insert, update on public.household_invites to authenticated;
-- Dogs and walks are tombstoned, never deleted: a hard delete would also
-- slip past Realtime's row level security (ADR 0008).
grant select, insert, update on public.dogs to authenticated;
grant select, insert, update on public.walks to authenticated;
grant select, insert, delete on public.walk_dogs to authenticated;
grant select, insert, update on public.member_profiles to authenticated;
