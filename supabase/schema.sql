-- KMCT Community backend schema (Supabase PostgreSQL)
-- Apply in Supabase SQL Editor. RLS is enabled on every user-facing table.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique not null check (char_length(username) between 3 and 24),
  display_name text not null default 'Member',
  avatar_url text,
  bio text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null default 'post' check (kind in ('post','meme','confession','poll','event','lost_found')),
  body text not null check (char_length(body) between 1 and 5000),
  image_url text,
  is_anonymous boolean not null default false,
  poll_options jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.post_comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 2000),
  created_at timestamptz not null default now()
);

create table if not exists public.post_likes (
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id,user_id)
);

create table if not exists public.poll_votes (
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  option_index integer not null check (option_index >= 0),
  created_at timestamptz not null default now(),
  primary key (post_id,user_id)
);

create table if not exists public.friend_requests (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references public.profiles(id) on delete cascade,
  receiver_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted','declined','cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (sender_id <> receiver_id),
  unique (sender_id, receiver_id)
);

create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now()
);

create table if not exists public.conversation_members (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (conversation_id,user_id)
);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 5000),
  created_at timestamptz not null default now(),
  read_at timestamptz
);

create table if not exists public.user_presence (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  is_online boolean not null default false,
  last_seen_at timestamptz not null default now()
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  actor_id uuid references public.profiles(id) on delete set null,
  kind text not null check (kind in ('friend_request','friend_accepted','message','comment','like','poll_vote','system')),
  entity_id uuid,
  body text not null default '',
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists posts_created_at_idx on public.posts(created_at desc);
create index if not exists posts_author_idx on public.posts(author_id,created_at desc);
create index if not exists comments_post_idx on public.post_comments(post_id,created_at);
create index if not exists messages_conversation_idx on public.messages(conversation_id,created_at);
create index if not exists friend_requests_receiver_idx on public.friend_requests(receiver_id,status,created_at desc);
create index if not exists notifications_user_idx on public.notifications(user_id,created_at desc);

-- Keep profiles in sync when email/password users sign up.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  base_name text;
begin
  base_name := lower(regexp_replace(coalesce(new.raw_user_meta_data->>'username', split_part(coalesce(new.email,'member'), '@', 1)), '[^a-zA-Z0-9_]', '', 'g'));
  if char_length(base_name) < 3 then base_name := 'member' || substr(new.id::text,1,6); end if;
  insert into public.profiles(id, username, display_name)
  values (new.id, left(base_name,18) || '_' || substr(new.id::text,1,5), coalesce(nullif(new.raw_user_meta_data->>'display_name',''), 'Member'))
  on conflict (id) do nothing;
  insert into public.user_presence(user_id) values(new.id) on conflict do nothing;
  return new;
end; $$;

drop trigger if exists on_auth_user_created_kmct on auth.users;
create trigger on_auth_user_created_kmct after insert on auth.users
for each row execute procedure public.handle_new_user();

-- Friend check helper. SECURITY DEFINER avoids recursive RLS evaluation.
create or replace function public.are_friends(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.friend_requests fr
    where fr.status='accepted'
      and ((fr.sender_id=a and fr.receiver_id=b) or (fr.sender_id=b and fr.receiver_id=a))
  );
$$;

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

drop policy if exists "profiles visible to authenticated users" on public.profiles;
create policy "profiles visible to authenticated users" on public.profiles for select to authenticated using (true);
drop policy if exists "users update own profile" on public.profiles;
create policy "users update own profile" on public.profiles for update to authenticated using (id=auth.uid()) with check (id=auth.uid());

drop policy if exists "signed in users read posts" on public.posts;
create policy "signed in users read posts" on public.posts for select to authenticated using (true);
drop policy if exists "users create own posts" on public.posts;
create policy "users create own posts" on public.posts for insert to authenticated with check (author_id=auth.uid());
drop policy if exists "users edit own posts" on public.posts;
create policy "users edit own posts" on public.posts for update to authenticated using (author_id=auth.uid()) with check (author_id=auth.uid());
drop policy if exists "users delete own posts" on public.posts;
create policy "users delete own posts" on public.posts for delete to authenticated using (author_id=auth.uid());

drop policy if exists "comments readable by signed in users" on public.post_comments;
create policy "comments readable by signed in users" on public.post_comments for select to authenticated using (true);
drop policy if exists "users add own comments" on public.post_comments;
create policy "users add own comments" on public.post_comments for insert to authenticated with check (author_id=auth.uid());
drop policy if exists "users delete own comments" on public.post_comments;
create policy "users delete own comments" on public.post_comments for delete to authenticated using (author_id=auth.uid());

drop policy if exists "likes readable by signed in users" on public.post_likes;
create policy "likes readable by signed in users" on public.post_likes for select to authenticated using (true);
drop policy if exists "users like as self" on public.post_likes;
create policy "users like as self" on public.post_likes for insert to authenticated with check (user_id=auth.uid());
drop policy if exists "users unlike as self" on public.post_likes;
create policy "users unlike as self" on public.post_likes for delete to authenticated using (user_id=auth.uid());

drop policy if exists "votes readable by signed in users" on public.poll_votes;
create policy "votes readable by signed in users" on public.poll_votes for select to authenticated using (true);
drop policy if exists "users vote as self" on public.poll_votes;
create policy "users vote as self" on public.poll_votes for insert to authenticated with check (user_id=auth.uid());

drop policy if exists "friend request participants read" on public.friend_requests;
create policy "friend request participants read" on public.friend_requests for select to authenticated using (sender_id=auth.uid() or receiver_id=auth.uid());
drop policy if exists "users send friend requests" on public.friend_requests;
create policy "users send friend requests" on public.friend_requests for insert to authenticated with check (sender_id=auth.uid() and receiver_id<>auth.uid() and status='pending');
drop policy if exists "receiver or sender updates request" on public.friend_requests;
create policy "receiver or sender updates request" on public.friend_requests for update to authenticated using (sender_id=auth.uid() or receiver_id=auth.uid()) with check ((sender_id=auth.uid() or receiver_id=auth.uid()) and status in ('accepted','declined','cancelled'));

-- SECURITY DEFINER membership check prevents RLS recursion when policies on
-- conversations/messages need to verify membership in conversation_members.
create or replace function public.is_conversation_member(p_conversation_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $
  select exists (
    select 1 from public.conversation_members cm
    where cm.conversation_id = p_conversation_id and cm.user_id = auth.uid()
  );
$;
revoke all on function public.is_conversation_member(uuid) from public;
grant execute on function public.is_conversation_member(uuid) to authenticated;

drop policy if exists "conversation members read conversations" on public.conversations;
create policy "conversation members read conversations" on public.conversations for select to authenticated using (public.is_conversation_member(id));
drop policy if exists "members can see membership" on public.conversation_members;
create policy "members can see membership" on public.conversation_members for select to authenticated using (public.is_conversation_member(conversation_id));
drop policy if exists "users can create own membership" on public.conversation_members;
create policy "users can create own membership" on public.conversation_members for insert to authenticated with check (user_id=auth.uid());
drop policy if exists "conversation members read messages" on public.messages;
create policy "conversation members read messages" on public.messages for select to authenticated using (public.is_conversation_member(conversation_id));
drop policy if exists "members send messages only as self" on public.messages;
create policy "members send messages only as self" on public.messages for insert to authenticated with check (sender_id=auth.uid() and public.is_conversation_member(conversation_id));

drop policy if exists "presence visible to authenticated users" on public.user_presence;
create policy "presence visible to authenticated users" on public.user_presence for select to authenticated using (true);
drop policy if exists "users update own presence" on public.user_presence;
create policy "users update own presence" on public.user_presence for update to authenticated using (user_id=auth.uid()) with check (user_id=auth.uid());

drop policy if exists "users read own notifications" on public.notifications;
create policy "users read own notifications" on public.notifications for select to authenticated using (user_id=auth.uid());
drop policy if exists "users mark own notifications read" on public.notifications;
create policy "users mark own notifications read" on public.notifications for update to authenticated using (user_id=auth.uid()) with check (user_id=auth.uid());

-- Required before live chat/presence: enable Realtime for messages and user_presence in Supabase dashboard.
-- Never put a service_role key in browser code. Use only the public anon/publishable key with these RLS policies.


-- Chat repair: keep this section in schema.sql so fresh installs and existing
-- deployments receive the same conversation columns and supported types.
alter table public.conversations
  add column if not exists title text,
  add column if not exists conversation_type text;

update public.conversations
set conversation_type = case
  when conversation_type in ('global', 'private', 'group') then conversation_type
  else 'private'
end
where conversation_type is null or conversation_type not in ('global', 'private', 'group');

update public.conversations
set title = case
  when conversation_type = 'global' then '# general'
  when title is null or btrim(title) = '' then 'Private chat'
  else title
end
where title is null or btrim(title) = '';

alter table public.conversations
  alter column conversation_type set default 'private',
  alter column conversation_type set not null,
  alter column title set default 'Private chat';

alter table public.conversations
  drop constraint if exists conversations_conversation_type_check;
alter table public.conversations
  add constraint conversations_conversation_type_check
  check (conversation_type in ('global', 'private', 'group'));

create unique index if not exists conversations_one_global_room_idx
  on public.conversations (conversation_type)
  where conversation_type = 'global';

create or replace function public.join_global_chat()
returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  room_id uuid;
  member_id uuid := auth.uid();
begin
  if member_id is null then raise exception 'Please sign in to join the general chat.'; end if;
  select c.id into room_id from public.conversations c where c.conversation_type = 'global' limit 1;
  if room_id is null then
    insert into public.conversations (title, conversation_type)
    values ('# general', 'global')
    on conflict (conversation_type) where conversation_type = 'global' do nothing
    returning id into room_id;
    if room_id is null then
      select c.id into room_id from public.conversations c where c.conversation_type = 'global' limit 1;
    end if;
  end if;
  insert into public.conversation_members (conversation_id, user_id)
  values (room_id, member_id) on conflict (conversation_id, user_id) do nothing;
  return room_id;
end;
$$;

create or replace function public.start_friend_conversation(p_friend uuid)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  member_id uuid := auth.uid();
  chat_id uuid;
begin
  if member_id is null then raise exception 'Please sign in to start a private chat.'; end if;
  if p_friend is null or p_friend = member_id then raise exception 'Choose another member.'; end if;
  if not public.are_friends(member_id, p_friend) then
    raise exception 'Private chat is available only after the friend request is accepted.';
  end if;
  select cm1.conversation_id into chat_id
  from public.conversation_members cm1
  join public.conversation_members cm2 on cm2.conversation_id = cm1.conversation_id
  join public.conversations c on c.id = cm1.conversation_id
  where c.conversation_type = 'private'
    and cm1.user_id = member_id and cm2.user_id = p_friend
    and (select count(*) from public.conversation_members cm3 where cm3.conversation_id = c.id) = 2
  limit 1;
  if chat_id is null then
    insert into public.conversations (title, conversation_type)
    values ('Private chat', 'private') returning id into chat_id;
    insert into public.conversation_members (conversation_id, user_id)
    values (chat_id, member_id), (chat_id, p_friend)
    on conflict (conversation_id, user_id) do nothing;
  end if;
  return chat_id;
end;
$$;

revoke all on function public.join_global_chat() from public;
revoke all on function public.start_friend_conversation(uuid) from public;
grant execute on function public.join_global_chat() to authenticated;
grant execute on function public.start_friend_conversation(uuid) to authenticated;
