-- Make member discovery work for every signed-in member and enforce unique usernames.
-- Apply in the Supabase SQL Editor if migrations are not automatically applied.

alter table public.profiles enable row level security;

drop policy if exists "authenticated members can discover profiles" on public.profiles;
create policy "authenticated members can discover profiles"
on public.profiles
for select
to authenticated
using (true);

create unique index if not exists profiles_username_lower_unique_idx
on public.profiles (lower(username))
where username is not null and btrim(username) <> '';

