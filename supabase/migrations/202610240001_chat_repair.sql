-- KMCT Community chat repair and global room setup.
-- Safe to run in Supabase SQL Editor; preserves existing conversations and messages.

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
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  room_id uuid;
  member_id uuid := auth.uid();
begin
  if member_id is null then
    raise exception 'Please sign in to join the general chat.';
  end if;

  select c.id into room_id
  from public.conversations c
  where c.conversation_type = 'global'
  limit 1;

  if room_id is null then
    insert into public.conversations (title, conversation_type)
    values ('# general', 'global')
    on conflict (conversation_type) where conversation_type = 'global' do nothing
    returning id into room_id;

    if room_id is null then
      select c.id into room_id
      from public.conversations c
      where c.conversation_type = 'global'
      limit 1;
    end if;
  end if;

  insert into public.conversation_members (conversation_id, user_id)
  values (room_id, member_id)
  on conflict (conversation_id, user_id) do nothing;

  return room_id;
end;
$$;

create or replace function public.start_friend_conversation(p_friend uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  member_id uuid := auth.uid();
  chat_id uuid;
begin
  if member_id is null then
    raise exception 'Please sign in to start a private chat.';
  end if;
  if p_friend is null or p_friend = member_id then
    raise exception 'Choose another member.';
  end if;
  if not public.are_friends(member_id, p_friend) then
    raise exception 'Private chat is available only after the friend request is accepted.';
  end if;

  select cm1.conversation_id into chat_id
  from public.conversation_members cm1
  join public.conversation_members cm2
    on cm2.conversation_id = cm1.conversation_id
  join public.conversations c
    on c.id = cm1.conversation_id
  where c.conversation_type = 'private'
    and cm1.user_id = member_id
    and cm2.user_id = p_friend
    and (select count(*) from public.conversation_members cm3
         where cm3.conversation_id = c.id) = 2
  limit 1;

  if chat_id is null then
    insert into public.conversations (title, conversation_type)
    values ('Private chat', 'private')
    returning id into chat_id;

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

-- Keep existing conversations readable only by their members; no public message access.
