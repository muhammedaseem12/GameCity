-- KMCT Community v2 backend migration. Safe to run after schema.sql.
create extension if not exists pgcrypto;
alter table public.conversations add column if not exists title text;
alter table public.conversations add column if not exists conversation_type text not null default 'direct';
create unique index if not exists one_global_room on public.conversations ((conversation_type)) where conversation_type='global';

create or replace function public.join_global_chat()
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare room_id uuid;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 select id into room_id from public.conversations where conversation_type='global' limit 1;
 if room_id is null then
  insert into public.conversations(title,conversation_type) values('KMCT Global Chat','global') returning id into room_id;
 end if;
 insert into public.conversation_members(conversation_id,user_id) values(room_id,auth.uid()) on conflict do nothing;
 return room_id;
end; $$;

create or replace function public.start_friend_conversation(p_friend uuid)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare room_id uuid;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if not public.are_friends(auth.uid(),p_friend) then raise exception 'You can message only accepted friends'; end if;
 select c.id into room_id from public.conversations c
 where c.conversation_type='direct'
 and exists(select 1 from public.conversation_members a where a.conversation_id=c.id and a.user_id=auth.uid())
 and exists(select 1 from public.conversation_members b where b.conversation_id=c.id and b.user_id=p_friend)
 limit 1;
 if room_id is null then
  insert into public.conversations(title,conversation_type) values('Private chat','direct') returning id into room_id;
  insert into public.conversation_members(conversation_id,user_id) values(room_id,auth.uid()),(room_id,p_friend) on conflict do nothing;
 end if;
 return room_id;
end; $$;
grant execute on function public.join_global_chat() to authenticated;
grant execute on function public.start_friend_conversation(uuid) to authenticated;
grant execute on function public.are_friends(uuid,uuid) to authenticated;

-- Membership reads must not use a recursive policy.
drop policy if exists "members can see membership" on public.conversation_members;
create policy "members can see membership" on public.conversation_members for select to authenticated
using (user_id=auth.uid());
-- Explicit API privileges; RLS still decides which rows are accessible.
grant usage on schema public to anon, authenticated;
grant select on public.posts,public.profiles,public.post_comments,public.post_likes,public.poll_votes,public.user_presence to authenticated;
grant insert,update,delete on public.posts,public.post_comments,public.post_likes,public.poll_votes to authenticated;
grant select,insert,update,delete on public.friend_requests to authenticated;
grant select,insert on public.conversations,public.conversation_members,public.messages to authenticated;
grant select,update on public.user_presence,public.notifications to authenticated;
-- Enable realtime for incoming chat messages.
do $$ begin
 alter publication supabase_realtime add table public.messages;
exception when duplicate_object then null; when undefined_object then null;
end $$;
