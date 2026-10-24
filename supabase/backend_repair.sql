-- KMCT Community backend repair
-- Run this in Supabase SQL Editor AFTER supabase/schema.sql and
-- supabase/community_features.sql. Safe to re-run.
-- This does not delete user data.

create extension if not exists pgcrypto;

-- Fail early with a useful message if the base schema wasn't installed.
do $$
begin
  if to_regclass('public.profiles') is null
     or to_regclass('public.posts') is null
     or to_regclass('public.post_comments') is null
     or to_regclass('public.post_likes') is null
     or to_regclass('public.poll_votes') is null
     or to_regclass('public.friend_requests') is null
     or to_regclass('public.conversations') is null
     or to_regclass('public.conversation_members') is null
     or to_regclass('public.messages') is null
     or to_regclass('public.user_presence') is null
     or to_regclass('public.notifications') is null then
    raise exception 'KMCT base schema is incomplete. Run supabase/schema.sql first, then supabase/community_features.sql, then rerun this repair.';
  end if;
end $$;

-- API grants. RLS policies below continue to restrict row-level access.
grant usage on schema public to authenticated;
grant select, update on public.profiles to authenticated;
grant select, insert, update, delete on public.posts to authenticated;
grant select, insert, delete on public.post_comments to authenticated;
grant select, insert, delete on public.post_likes to authenticated;
grant select, insert, delete on public.poll_votes to authenticated;
grant select, insert, update on public.friend_requests to authenticated;
grant select, insert on public.conversations to authenticated;
grant select, insert on public.conversation_members to authenticated;
grant select, insert, update on public.messages to authenticated;
grant select, update on public.user_presence to authenticated;
grant select, update on public.notifications to authenticated;

-- Ensure required RLS is on.
alter table public.profiles enable row level security;
alter table public.posts enable row level security;
alter table public.post_comments enable row level security;
alter table public.post_likes enable row level security;
alter table public.poll_votes enable row level security;
alter table public.friend_requests enable row level security;
alter table public.conversations enable row level security;
alter table public.conversation_members enable row level security;
alter table public.messages enable row level security;
alter table public.user_presence enable row level security;
alter table public.notifications enable row level security;

-- Repair the profile creation trigger used after Supabase Auth sign-up.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  base_name text;
begin
  base_name := lower(regexp_replace(
    coalesce(new.raw_user_meta_data->>'username', split_part(coalesce(new.email,'member'), '@', 1)),
    '[^a-zA-Z0-9_]', '', 'g'
  ));
  if char_length(base_name) < 3 then
    base_name := 'member' || substr(new.id::text,1,6);
  end if;

  insert into public.profiles(id, username, display_name)
  values (
    new.id,
    left(base_name,18) || '_' || substr(new.id::text,1,5),
    coalesce(nullif(new.raw_user_meta_data->>'display_name',''), 'Member')
  )
  on conflict (id) do nothing;

  insert into public.user_presence(user_id)
  values (new.id)
  on conflict (user_id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created_kmct on auth.users;
create trigger on_auth_user_created_kmct
after insert on auth.users
for each row execute procedure public.handle_new_user();

-- Avoid recursive membership policy checks.
create or replace function public.is_conversation_member(
  p_conversation uuid,
  p_user uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.conversation_members cm
    where cm.conversation_id = p_conversation
      and cm.user_id = p_user
  );
$$;

grant execute on function public.is_conversation_member(uuid,uuid) to authenticated;

drop policy if exists "members can see membership" on public.conversation_members;
create policy "members can see membership"
on public.conversation_members for select to authenticated
using (public.is_conversation_member(conversation_id, auth.uid()));

drop policy if exists "conversation members read conversations" on public.conversations;
create policy "conversation members read conversations"
on public.conversations for select to authenticated
using (public.is_conversation_member(id, auth.uid()));

drop policy if exists "conversation members read messages" on public.messages;
create policy "conversation members read messages"
on public.messages for select to authenticated
using (public.is_conversation_member(conversation_id, auth.uid()));

drop policy if exists "members send messages only as self" on public.messages;
create policy "members send messages only as self"
on public.messages for insert to authenticated
with check (
  sender_id = auth.uid()
  and public.is_conversation_member(conversation_id, auth.uid())
);

-- Required indexes.
create index if not exists posts_created_at_idx on public.posts(created_at desc);
create index if not exists posts_author_idx on public.posts(author_id, created_at desc);
create index if not exists comments_post_idx on public.post_comments(post_id, created_at);
create index if not exists messages_conversation_idx on public.messages(conversation_id, created_at);
create index if not exists friend_requests_receiver_idx on public.friend_requests(receiver_id, status, created_at desc);
create index if not exists notifications_user_idx on public.notifications(user_id, created_at desc);

-- Add live messages/presence to Realtime where available.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1 from pg_publication_tables
      where pubname='supabase_realtime' and schemaname='public' and tablename='messages'
    ) then
      alter publication supabase_realtime add table public.messages;
    end if;
    if not exists (
      select 1 from pg_publication_tables
      where pubname='supabase_realtime' and schemaname='public' and tablename='user_presence'
    ) then
      alter publication supabase_realtime add table public.user_presence;
    end if;
  end if;
end $$;

-- Verification result: every expected backend table should be listed.
select table_name
from information_schema.tables
where table_schema = 'public'
  and table_name in (
    'profiles','posts','post_comments','post_likes','poll_votes',
    'friend_requests','conversations','conversation_members',
    'messages','user_presence','notifications'
  )
order by table_name;
