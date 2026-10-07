-- Supabase's default privileges grant EXECUTE on every new function in public
-- to anon directly, not only through PUBLIC, so `revoke ... from public` left
-- anon able to call accept_household_invite and delete_my_account (found in
-- production on 2026-10-08). Both refuse without a session ('not signed in'),
-- so nothing leaked; this makes the rule hold by grant, not only by code.

revoke execute on function public.accept_household_invite(text) from anon;
revoke execute on function public.delete_my_account() from anon;

-- And for every function created later in public by this role.
alter default privileges in schema public revoke execute on functions from anon;
